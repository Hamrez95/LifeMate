import 'package:lifemate_client/lifemate_client.dart';

import '../models/care_home_snapshot.dart';

class CareHomeAggregator {
  CareHomeAggregator(this._api);

  final LifeMateApiClient _api;

  Future<CareHomeSnapshot> load({DateTime? now}) async {
    final reference = now ?? DateTime.now();
    final base = await Future.wait<dynamic>([
      _api.getCurrentUser(),
      _api.getCareRelationships(),
    ]);
    final currentUser = base[0] as Map<String, dynamic>;
    final rawRelationships = base[1] as List<Map<String, dynamic>>;
    final user = currentUser['user'] is Map<String, dynamic>
        ? currentUser['user'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final currentUserId = user['id']?.toString();
    final relationships = rawRelationships
        .where(
          (value) =>
              value['status']?.toString().toLowerCase() == 'active' &&
              value['caregiverUserId']?.toString() == currentUserId,
        )
        .map(CareHomeRelationship.fromJson)
        .where(
          (relationship) =>
              relationship.relationshipId.isNotEmpty &&
              relationship.patientUserId.isNotEmpty,
        )
        .toList(growable: false);

    final startOfToday = DateTime(
      reference.year,
      reference.month,
      reference.day,
    );
    // Keep a short look-back so a still-scheduled overdue dose cannot silently
    // disappear from the caregiver queue. The complete request window remains
    // bounded to 31 days for the existing care-event contract.
    final fromDate = startOfToday.subtract(const Duration(days: 7));
    final toDate = startOfToday.add(const Duration(days: 23));
    final dosesByPatient = <String, List<Map<String, dynamic>>>{};
    final eventsByPatient = <String, List<Map<String, dynamic>>>{};

    await Future.wait(
      relationships.map((relationship) async {
        final values = await Future.wait<dynamic>([
          _api.getCareRecipientDoseOccurrences(
            patientUserId: relationship.patientUserId,
            fromDate: fromDate,
            toDate: toDate,
          ),
          _api.getCareRecipientCareEvents(
            patientUserId: relationship.patientUserId,
            fromDate: fromDate,
            toDate: toDate,
          ),
        ]);
        dosesByPatient[relationship.patientUserId] =
            values[0] as List<Map<String, dynamic>>;
        eventsByPatient[relationship.patientUserId] =
            values[1] as List<Map<String, dynamic>>;
      }),
    );

    final companion = await _loadCompanion(relationships);
    return buildSnapshot(
      currentUser: currentUser,
      relationships: relationships,
      dosesByPatient: dosesByPatient,
      eventsByPatient: eventsByPatient,
      companion: companion,
      now: reference,
    );
  }

  Future<CareCompanionHomeSummary> _loadCompanion(
    List<CareHomeRelationship> relationships,
  ) async {
    // #109 scopes are relationship-bound and default-off. Do not infer access
    // from the legacy broad flag or the relationship type: ask the server for
    // each exact relationship and fail closed when it declines the request.
    CareHomeRelationship? unavailableRelationship;
    String? unavailableError;
    for (final relationship in relationships) {
      try {
        final value = await _api.getCareRecipientWomenCalendar(
          patientUserId: relationship.patientUserId,
        );
        return CareCompanionHomeSummary.fromApi(
          relationship: relationship,
          value: value,
        );
      } on LifeMateApiException catch (error) {
        if (error.code == 'women_calendar_access_denied') continue;
        unavailableRelationship ??= relationship;
        unavailableError ??= error.code;
      } catch (_) {
        unavailableRelationship ??= relationship;
        unavailableError ??= 'companion_summary_unavailable';
      }
    }
    return unavailableRelationship == null
        ? CareCompanionHomeSummary.locked()
        : CareCompanionHomeSummary.unavailable(
            relationship: unavailableRelationship,
            errorCode: unavailableError,
          );
  }

  static CareHomeSnapshot buildSnapshot({
    required Map<String, dynamic> currentUser,
    required List<CareHomeRelationship> relationships,
    required Map<String, List<Map<String, dynamic>>> dosesByPatient,
    required Map<String, List<Map<String, dynamic>>> eventsByPatient,
    required CareCompanionHomeSummary companion,
    required DateTime now,
  }) {
    final allItems = <CareHomeTreatmentItem>[];
    for (final relationship in relationships) {
      final doses = dosesByPatient[relationship.patientUserId] ?? const [];
      for (final dose in doses) {
        final item = _fromDose(relationship, dose);
        if (item != null) allItems.add(item);
      }
      final events = eventsByPatient[relationship.patientUserId] ?? const [];
      for (final event in events) {
        final item = _fromCareEvent(relationship, event);
        if (item != null) allItems.add(item);
      }
    }

    final queue = allItems
        .where((item) => item.isQueueEligible && !item.isIrrelevant)
        .toList(growable: false);
    final today = allItems
        .where(
          (item) => !item.isIrrelevant && _isSameDay(item.scheduledAt, now),
        )
        .toList(growable: false);
    _sortBySchedule(queue);
    _sortBySchedule(today);

    return CareHomeSnapshot(
      currentUser: currentUser,
      relationships: List<CareHomeRelationship>.unmodifiable(relationships),
      queueItems: List<CareHomeTreatmentItem>.unmodifiable(queue),
      todayItems: List<CareHomeTreatmentItem>.unmodifiable(today),
      companion: companion,
    );
  }

  static CareHomeTreatmentItem? _fromDose(
    CareHomeRelationship relationship,
    Map<String, dynamic> dose,
  ) {
    final scheduledAt = _scheduledAt(dose);
    if (scheduledAt == null) return null;
    final title =
        _text(dose['medicationName']) ??
        LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(fa: 'دارو', en: "Medication"),
          en: "medicine",
        );
    return CareHomeTreatmentItem(
      relationshipId: relationship.relationshipId,
      patientUserId: relationship.patientUserId,
      patientDisplayName: relationship.patientDisplayName,
      patientProfilePhotoUrl: relationship.patientProfilePhotoUrl,
      patientAvatarKey: relationship.patientAvatarKey,
      type: CareItemType.medication,
      treatmentId: _text(dose['treatmentPlanId']) ?? _text(dose['id']) ?? '',
      occurrenceId: _text(dose['id']) ?? '',
      title: title,
      subtitle: _text(dose['doseText']) ?? '',
      scheduledAt: scheduledAt,
      scheduledLocalTime: _timeText(dose['scheduledLocalTime'], scheduledAt),
      status: (_text(dose['status']) ?? 'scheduled').toLowerCase(),
      raw: Map<String, dynamic>.unmodifiable(dose),
    );
  }

  static CareHomeTreatmentItem? _fromCareEvent(
    CareHomeRelationship relationship,
    Map<String, dynamic> event,
  ) {
    final scheduledAt = _scheduledAt(event);
    if (scheduledAt == null) return null;
    final careItem = CareItem.fromCareEvent(event);
    final isInjection = careItem.type == CareItemType.injection;
    final title = isInjection
        ? _text(event['medicationName']) ?? careItem.title
        : careItem.title;
    final subtitleValues = isInjection
        ? <dynamic>[
            event['doseText'],
            event['administrationRoute'],
            event['centerName'],
          ]
        : <dynamic>[
            event['providerName'],
            event['specialty'],
            event['centerName'],
          ];
    return CareHomeTreatmentItem(
      relationshipId: relationship.relationshipId,
      patientUserId: relationship.patientUserId,
      patientDisplayName: relationship.patientDisplayName,
      patientProfilePhotoUrl: relationship.patientProfilePhotoUrl,
      patientAvatarKey: relationship.patientAvatarKey,
      type: careItem.type,
      treatmentId:
          _text(event['seriesId']) ?? _text(event['id']) ?? careItem.id,
      occurrenceId:
          _text(event['occurrenceId']) ?? _text(event['id']) ?? careItem.id,
      title: title,
      subtitle: subtitleValues
          .map(_text)
          .whereType<String>()
          .where((value) => value.isNotEmpty)
          .join(' • '),
      scheduledAt: scheduledAt,
      scheduledLocalTime: _timeText(event['scheduledLocalTime'], scheduledAt),
      status: (_text(event['status']) ?? 'scheduled').toLowerCase(),
      raw: Map<String, dynamic>.unmodifiable(event),
    );
  }

  static DateTime? _scheduledAt(Map<String, dynamic> value) {
    final utc = DateTime.tryParse(_text(value['scheduledAtUtc']) ?? '');
    if (utc != null) return utc.toLocal();
    final date = DateTime.tryParse(_text(value['scheduledLocalDate']) ?? '');
    final time = _text(value['scheduledLocalTime']);
    if (date == null) return null;
    if (time == null) return date;
    final parts = time.split(':');
    final hour = parts.isEmpty ? 0 : int.tryParse(parts[0]) ?? 0;
    final minute = parts.length < 2 ? 0 : int.tryParse(parts[1]) ?? 0;
    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  static String _timeText(dynamic value, DateTime fallback) {
    final text = _text(value);
    if (text != null && text.length >= 5) return text.substring(0, 5);
    return '${fallback.hour.toString().padLeft(2, '0')}:'
        '${fallback.minute.toString().padLeft(2, '0')}';
  }

  static void _sortBySchedule(List<CareHomeTreatmentItem> items) {
    items.sort((left, right) {
      final byTime = left.scheduledAt.compareTo(right.scheduledAt);
      if (byTime != 0) return byTime;
      final byPatient = left.patientUserId.compareTo(right.patientUserId);
      if (byPatient != 0) return byPatient;
      return left.occurrenceId.compareTo(right.occurrenceId);
    });
  }

  static bool _isSameDay(DateTime left, DateTime right) =>
      left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;

  static String? _text(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}
