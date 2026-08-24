class CareRecipientAlert {
  const CareRecipientAlert({
    required this.patientUserId,
    required this.patientName,
    required this.occurrenceId,
    required this.title,
    required this.scheduledAtUtc,
    required this.kind,
    required this.status,
    this.subtitle = '',
  });

  final String patientUserId;
  final String patientName;
  final String occurrenceId;
  final String title;
  final String subtitle;
  final DateTime scheduledAtUtc;
  final String kind;
  final String status;

  bool get isMissed => const {'missed', 'skipped'}.contains(status.toLowerCase());
}

List<CareRecipientAlert> selectLatestMissedAlertPerPatient(
  Iterable<CareRecipientAlert> alerts, {
  DateTime? nowUtc,
}) {
  final now = (nowUtc ?? DateTime.now().toUtc()).toUtc();
  final selected = <String, CareRecipientAlert>{};
  for (final alert in alerts) {
    final scheduled = alert.scheduledAtUtc.toUtc();
    if (!alert.isMissed || scheduled.isAfter(now)) continue;
    final existing = selected[alert.patientUserId];
    if (existing == null || _compareAlert(alert, existing) < 0) {
      selected[alert.patientUserId] = alert;
    }
  }
  final result = selected.values.toList(growable: false)
    ..sort(_compareAlert);
  return result;
}

int _compareAlert(CareRecipientAlert left, CareRecipientAlert right) {
  final byTime = right.scheduledAtUtc.toUtc().compareTo(
    left.scheduledAtUtc.toUtc(),
  );
  if (byTime != 0) return byTime;
  final byPatient = left.patientUserId.compareTo(right.patientUserId);
  if (byPatient != 0) return byPatient;
  return left.occurrenceId.compareTo(right.occurrenceId);
}
