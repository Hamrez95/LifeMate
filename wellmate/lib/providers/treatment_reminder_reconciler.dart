import 'package:lifemate_client/lifemate_client.dart';

import '../models/schedule_item_model.dart';

List<ScheduleItemModel> reconcileTreatmentReminderWindow({
  required List<ScheduleItemModel> currentItems,
  required Map<String, dynamic> serverSnapshot,
  required DateTime now,
}) {
  final rawPlans = serverSnapshot['treatmentPlans'];
  final rawOccurrences = serverSnapshot['doseOccurrences'];
  if (rawPlans is! List || rawOccurrences is! List) {
    throw StateError('Authoritative treatment snapshot is incomplete.');
  }

  final plans = rawPlans.whereType<Map>().map((raw) {
    return raw.map((key, value) => MapEntry(key.toString(), value));
  }).toList(growable: false);
  final occurrences = rawOccurrences.whereType<Map>().map((raw) {
    return raw.map((key, value) => MapEntry(key.toString(), value));
  }).toList(growable: false);
  if (plans.length != rawPlans.length || occurrences.length != rawOccurrences.length) {
    throw StateError('Authoritative treatment snapshot contains invalid rows.');
  }

  final plansById = <String, Map<String, dynamic>>{
    for (final plan in plans)
      if ((plan['id']?.toString().trim() ?? '').isNotEmpty)
        plan['id'].toString(): plan,
  };

  final freshMedicine = <ScheduleItemModel>[];
  for (final occurrence in occurrences) {
    final id = occurrence['id']?.toString().trim() ?? '';
    final treatmentPlanId =
        occurrence['treatmentPlanId']?.toString().trim() ?? '';
    if (id.isEmpty || treatmentPlanId.isEmpty) {
      throw StateError('Authoritative treatment occurrence is missing identity.');
    }
    final plan = plansById[treatmentPlanId];
    if (plan == null) {
      throw StateError('Authoritative treatment occurrence has no plan.');
    }

    final status = (occurrence['status'] ?? 'scheduled').toString().toLowerCase();
    final pending = occurrence['pendingSync'] == true || status == 'pending_sync';
    if (pending || status != 'scheduled') continue;

    final scheduledAtUtc = DateTime.tryParse(
      occurrence['scheduledAtUtc']?.toString() ?? '',
    )?.toUtc();
    if (scheduledAtUtc == null || !scheduledAtUtc.isAfter(now.toUtc())) continue;

    final medication = plan['medication'] is Map
        ? (plan['medication'] as Map).map(
            (key, value) => MapEntry(key.toString(), value),
          )
        : const <String, dynamic>{};
    final rawTime = occurrence['scheduledLocalTime']?.toString() ?? '';
    final startDate = DateTime.tryParse(
      occurrence['scheduledLocalDate']?.toString() ?? '',
    );

    freshMedicine.add(
      ScheduleItemModel(
        id: id,
        type: 'medicine',
        title: medication['name']?.toString().trim().isNotEmpty == true
            ? medication['name'].toString()
            : 'Medication',
        time: rawTime.length >= 5 ? rawTime.substring(0, 5) : rawTime,
        dosage: (plan['doseText'] ?? '').toString(),
        status: status,
        version: occurrence['version'] is int
            ? occurrence['version'] as int
            : int.tryParse(occurrence['version']?.toString() ?? '') ?? 1,
        scheduledAtUtc: scheduledAtUtc,
        startDate: startDate,
        intervalDays: 1,
        frequency: 'According to the treatment plan',
        patientReminderMinutesBefore: LifeMateReminderLeadTimes.normalize(
          occurrence['patientReminderMinutesBefore'],
          fallback: LifeMateReminderLeadTimes.defaultPatientMinutes,
        ),
        caregiverReminderMinutesBefore: LifeMateReminderLeadTimes.normalize(
          occurrence['caregiverReminderMinutesBefore'],
          fallback: LifeMateReminderLeadTimes.defaultCaregiverMinutes,
        ),
      ),
    );
  }

  return <ScheduleItemModel>[
    for (final item in currentItems)
      if (item.type != 'medicine') item,
    ...freshMedicine,
  ];
}
