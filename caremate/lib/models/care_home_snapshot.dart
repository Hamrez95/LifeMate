import 'package:lifemate_client/lifemate_client.dart';

class CareHomeRelationship {
  const CareHomeRelationship({
    required this.relationshipId,
    required this.patientUserId,
    required this.patientDisplayName,
    required this.canViewWomenCalendar,
    this.presentationType = 'unknown',
    this.patientProfilePhotoUrl,
    this.patientAvatarKey,
    this.patientPhoneNumber,
  });

  final String relationshipId;
  final String patientUserId;
  final String patientDisplayName;
  final String presentationType;
  final String? patientProfilePhotoUrl;
  final String? patientAvatarKey;
  final String? patientPhoneNumber;
  final bool canViewWomenCalendar;

  LifeMateRelationshipPresentationPolicy get presentationPolicy =>
      LifeMateRelationshipPresentationPolicy.fromRaw(presentationType);

  factory CareHomeRelationship.fromJson(Map<String, dynamic> value) {
    final name = value['patientDisplayName']?.toString().trim();
    return CareHomeRelationship(
      relationshipId: value['id']?.toString() ?? '',
      patientUserId: value['patientUserId']?.toString() ?? '',
      patientDisplayName: name == null || name.isEmpty
          ? LifeMateRuntimeLocale.select(
              fa: 'فرد تحت مراقبت',
              en: 'Person under care',
            )
          : name,
      presentationType: value['presentationType']?.toString() ?? 'unknown',
      patientProfilePhotoUrl: _nullableText(value['patientProfilePhotoUrl']),
      patientAvatarKey: _nullableText(value['patientAvatarKey']),
      patientPhoneNumber: _nullableText(value['patientPhoneNumber']),
      canViewWomenCalendar: value['canViewWomenCalendar'] == true,
    );
  }
}

class CareHomeTreatmentItem {
  const CareHomeTreatmentItem({
    required this.relationshipId,
    required this.patientUserId,
    required this.patientDisplayName,
    required this.type,
    required this.treatmentId,
    required this.occurrenceId,
    required this.title,
    required this.subtitle,
    required this.scheduledAt,
    required this.scheduledLocalTime,
    required this.status,
    required this.raw,
    this.presentationType = 'unknown',
    this.patientProfilePhotoUrl,
    this.patientAvatarKey,
  });

  final String relationshipId;
  final String patientUserId;
  final String patientDisplayName;
  final String presentationType;
  final String? patientProfilePhotoUrl;
  final String? patientAvatarKey;
  final CareItemType type;
  final String treatmentId;
  final String occurrenceId;
  final String title;
  final String subtitle;
  final DateTime scheduledAt;
  final String scheduledLocalTime;
  final String status;
  final Map<String, dynamic> raw;

  LifeMateRelationshipPresentationPolicy get presentationPolicy =>
      LifeMateRelationshipPresentationPolicy.fromRaw(presentationType);

  bool get isQueueEligible =>
      const <String>{'scheduled', 'pending'}.contains(status.toLowerCase());

  bool get isIrrelevant => const <String>{
    'cancelled',
    'archived',
    'inactive',
    'stopped',
  }.contains(status.toLowerCase());

  bool get isCompleted =>
      const <String>{'taken', 'completed'}.contains(status.toLowerCase());

  bool get isAlert =>
      const <String>{'missed', 'skipped'}.contains(status.toLowerCase());
}

class CareCompanionHomeSummary {
  const CareCompanionHomeSummary({
    required this.hasPermission,
    required this.available,
    this.relationship,
    this.cycleDay,
    this.cycleLength,
    this.mood,
    this.energyLevel,
    this.errorCode,
  });

  final bool hasPermission;
  final bool available;
  final CareHomeRelationship? relationship;
  final int? cycleDay;
  final int? cycleLength;
  final String? mood;
  final int? energyLevel;
  final String? errorCode;

  factory CareCompanionHomeSummary.locked() =>
      const CareCompanionHomeSummary(hasPermission: false, available: false);

  factory CareCompanionHomeSummary.unavailable({
    required CareHomeRelationship relationship,
    String? errorCode,
  }) => CareCompanionHomeSummary(
    hasPermission: true,
    available: false,
    relationship: relationship,
    errorCode: errorCode,
  );

  factory CareCompanionHomeSummary.fromApi({
    required CareHomeRelationship relationship,
    required Map<String, dynamic> value,
  }) {
    final estimate = _object(value['estimate']);
    final shared = _object(value['latestSharedDailyLog']);
    return CareCompanionHomeSummary(
      hasPermission: true,
      available: true,
      relationship: relationship,
      cycleDay: _intValue(estimate['cycleDay']),
      cycleLength: _intValue(estimate['cycleLength']),
      mood: _nullableText(shared['mood']),
      energyLevel: _intValue(shared['energyLevel']),
    );
  }
}

class CareHomeSnapshot {
  const CareHomeSnapshot({
    required this.currentUser,
    required this.relationships,
    required this.queueItems,
    required this.todayItems,
    required this.companion,
  });

  final Map<String, dynamic> currentUser;
  final List<CareHomeRelationship> relationships;
  final List<CareHomeTreatmentItem> queueItems;
  final List<CareHomeTreatmentItem> todayItems;
  final CareCompanionHomeSummary companion;

  CareHomeTreatmentItem? get currentTreatment =>
      queueItems.isEmpty ? null : queueItems.first;

  CareHomeTreatmentItem? get nextTreatment =>
      queueItems.length < 2 ? null : queueItems[1];

  int get completedToday => todayItems.where((item) => item.isCompleted).length;

  int get alertsToday => todayItems.where((item) => item.isAlert).length;

  int get pendingToday =>
      todayItems.where((item) => item.isQueueEligible).length;
}

String? _nullableText(dynamic value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

Map<String, dynamic> _object(dynamic value) =>
    value is Map<String, dynamic> ? value : const <String, dynamic>{};

int? _intValue(dynamic value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '');
}
