import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:lifemate_ui/lifemate_ui.dart';

import '../models/schedule_item_model.dart';

const wellMateGroupedMedicationPrefix = 'lifemate-medication-group:';

class GroupedMedicationDoseTarget {
  const GroupedMedicationDoseTarget({
    required this.occurrenceId,
    required this.version,
    required this.clientRequestId,
    required this.title,
  });

  final String occurrenceId;
  final int version;
  final String clientRequestId;
  final String title;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'occurrenceId': occurrenceId,
        'version': version,
        'clientRequestId': clientRequestId,
        'title': title,
      };

  static GroupedMedicationDoseTarget? fromJson(Map<String, dynamic> json) {
    final occurrenceId = json['occurrenceId']?.toString().trim() ?? '';
    final clientRequestId = json['clientRequestId']?.toString().trim() ?? '';
    final title = json['title']?.toString().trim() ?? '';
    final version = int.tryParse(json['version']?.toString() ?? '');
    if (occurrenceId.isEmpty ||
        clientRequestId.isEmpty ||
        title.isEmpty ||
        version == null ||
        version < 1) {
      return null;
    }
    return GroupedMedicationDoseTarget(
      occurrenceId: occurrenceId,
      version: version,
      clientRequestId: clientRequestId,
      title: title,
    );
  }
}

class GroupedMedicationNotificationTarget {
  const GroupedMedicationNotificationTarget({
    required this.groupKey,
    required this.isPersian,
    required this.doses,
  });

  final String groupKey;
  final bool isPersian;
  final List<GroupedMedicationDoseTarget> doses;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'groupKey': groupKey,
        'isPersian': isPersian,
        'doses': doses.map((dose) => dose.toJson()).toList(growable: false),
      };

  static GroupedMedicationNotificationTarget? fromJson(
    Map<String, dynamic> json,
  ) {
    final groupKey = json['groupKey']?.toString().trim() ?? '';
    final raw = json['doses'];
    if (groupKey.isEmpty || raw is! List) return null;
    final doses = raw
        .whereType<Map>()
        .map(
          (value) => GroupedMedicationDoseTarget.fromJson(
            Map<String, dynamic>.from(value),
          ),
        )
        .whereType<GroupedMedicationDoseTarget>()
        .toList(growable: false);
    if (doses.length < 2) return null;
    return GroupedMedicationNotificationTarget(
      groupKey: groupKey,
      isPersian: json['isPersian'] == true,
      doses: doses,
    );
  }
}

class GroupedMedicationCandidate {
  const GroupedMedicationCandidate({
    required this.item,
    required this.scheduledUtc,
    required this.triggerUtc,
  });

  final ScheduleItemModel item;
  final DateTime scheduledUtc;
  final DateTime triggerUtc;
}

Map<DateTime, List<GroupedMedicationCandidate>> groupMedicationCandidates(
  Iterable<GroupedMedicationCandidate> candidates,
) {
  final result = <DateTime, List<GroupedMedicationCandidate>>{};
  for (final candidate in candidates) {
    if (candidate.item.type != 'medicine' ||
        candidate.item.status != 'scheduled') {
      continue;
    }
    final normalized = candidate.triggerUtc.toUtc();
    result
        .putIfAbsent(normalized, () => <GroupedMedicationCandidate>[])
        .add(candidate);
  }
  result.removeWhere((_, values) => values.length < 2);
  for (final values in result.values) {
    values.sort((a, b) => a.item.id.compareTo(b.item.id));
  }
  return result;
}

/// Expands a changed medication occurrence set to the smallest complete set of
/// grouped-reminder dependencies that must be reconciled together.
///
/// A single edited dose can leave an old group and make an unchanged neighbor
/// become an individual reminder, or join a new group whose other members were
/// otherwise unchanged. Considering both old and desired memberships and taking
/// their transitive closure prevents either stale grouped alarms or accidental
/// full-window reminder churn. Only opaque occurrence IDs are handled here.
Set<String> expandAffectedMedicationOccurrenceIds({
  required Iterable<String> affectedOccurrenceIds,
  required Iterable<Iterable<String>> groupMemberships,
}) {
  final affected = affectedOccurrenceIds
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toSet();
  if (affected.isEmpty) return const <String>{};

  final groups = groupMemberships
      .map(
        (values) => values
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toSet(),
      )
      .where((values) => values.length >= 2)
      .toList(growable: false);

  var changed = true;
  while (changed) {
    changed = false;
    for (final group in groups) {
      if (!group.any(affected.contains)) continue;
      for (final occurrenceId in group) {
        if (affected.add(occurrenceId)) changed = true;
      }
    }
  }
  return Set<String>.unmodifiable(affected);
}

String encodeGroupedMedicationPayload(
  GroupedMedicationNotificationTarget target,
) {
  final encoded = base64Url.encode(
    utf8.encode(jsonEncode(target.toJson())),
  );
  return '$wellMateGroupedMedicationPrefix$encoded';
}

GroupedMedicationNotificationTarget? decodeGroupedMedicationPayload(
  String? payload,
) {
  if (payload == null || !payload.startsWith(wellMateGroupedMedicationPrefix)) {
    return null;
  }
  final encoded = payload.substring(wellMateGroupedMedicationPrefix.length);
  if (encoded.isEmpty) return null;
  try {
    final decoded = jsonDecode(utf8.decode(base64Url.decode(encoded)));
    if (decoded is! Map) return null;
    return GroupedMedicationNotificationTarget.fromJson(
      Map<String, dynamic>.from(decoded),
    );
  } catch (_) {
    return null;
  }
}

Locale _notificationLocale(bool isPersian) => Locale(isPersian ? 'fa' : 'en');

String groupedMedicationTitle(int count, bool isPersian) =>
    lifeMateMessages.text(
      'medication.grouped.notification.title',
      locale: _notificationLocale(isPersian),
      params: {'count': count},
    );

String groupedMedicationReviewAction(bool isPersian) => lifeMateMessages.text(
      'medication.grouped.notification.reviewAction',
      locale: _notificationLocale(isPersian),
    );

String groupedMedicationBody(
  Iterable<GroupedMedicationDoseTarget> doses,
  bool isPersian, {
  int maxNames = 3,
}) {
  final names = doses
      .map((dose) => dose.title.trim())
      .where((value) => value.isNotEmpty)
      .toList();
  final locale = _notificationLocale(isPersian);
  if (names.isEmpty) {
    return lifeMateMessages.text(
      'medication.grouped.notification.emptyBody',
      locale: locale,
    );
  }
  final visible = names.take(maxNames).join(isPersian ? '، ' : ', ');
  final hidden = names.length - maxNames;
  if (hidden <= 0) return visible;
  return lifeMateMessages.text(
    'medication.grouped.notification.more',
    locale: locale,
    params: {'visible': visible, 'count': hidden},
  );
}
