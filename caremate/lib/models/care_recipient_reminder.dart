class CareRecipientReminder {
  const CareRecipientReminder({
    required this.patientUserId,
    required this.patientName,
    required this.doseId,
    required this.medicationName,
    required this.doseText,
    required this.scheduledAtUtc,
  });

  final String patientUserId;
  final String patientName;
  final String doseId;
  final String medicationName;
  final String doseText;
  final DateTime scheduledAtUtc;
}

List<CareRecipientReminder> selectEarliestReminderPerPatient(
  Iterable<CareRecipientReminder> reminders, {
  DateTime? nowUtc,
}) {
  final now = (nowUtc ?? DateTime.now().toUtc()).toUtc();
  final selected = <String, CareRecipientReminder>{};
  for (final reminder in reminders) {
    final scheduled = reminder.scheduledAtUtc.toUtc();
    if (!scheduled.isAfter(now)) continue;
    final existing = selected[reminder.patientUserId];
    if (existing == null ||
        scheduled.isBefore(existing.scheduledAtUtc.toUtc())) {
      selected[reminder.patientUserId] = reminder;
    }
  }
  final result = selected.values.toList(growable: false)
    ..sort((a, b) => a.scheduledAtUtc.compareTo(b.scheduledAtUtc));
  return result;
}
