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
    if (existing == null || _compareReminder(reminder, existing) < 0) {
      selected[reminder.patientUserId] = reminder;
    }
  }
  final result = selected.values.toList(growable: false)
    ..sort(_compareReminder);
  return result;
}

int _compareReminder(
  CareRecipientReminder left,
  CareRecipientReminder right,
) {
  final byTime = left.scheduledAtUtc
      .toUtc()
      .compareTo(right.scheduledAtUtc.toUtc());
  if (byTime != 0) return byTime;
  final byPatient = left.patientUserId.compareTo(right.patientUserId);
  if (byPatient != 0) return byPatient;
  return left.doseId.compareTo(right.doseId);
}
