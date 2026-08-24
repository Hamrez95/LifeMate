import 'package:caremate/models/care_recipient_alert.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('selects the latest authoritative missed alert for each recipient', () {
    final now = DateTime.utc(2026, 8, 24, 9);
    final result = selectLatestMissedAlertPerPatient([
      CareRecipientAlert(
        patientUserId: 'p1',
        patientName: 'مامان جون',
        occurrenceId: 'old',
        title: 'متفورمین',
        scheduledAtUtc: DateTime.utc(2026, 8, 24, 7),
        kind: 'medication',
        status: 'missed',
      ),
      CareRecipientAlert(
        patientUserId: 'p1',
        patientName: 'مامان جون',
        occurrenceId: 'latest',
        title: 'آملودیپین',
        scheduledAtUtc: DateTime.utc(2026, 8, 24, 8),
        kind: 'medication',
        status: 'skipped',
      ),
      CareRecipientAlert(
        patientUserId: 'p2',
        patientName: 'بابا',
        occurrenceId: 'visit',
        title: 'ویزیت قلب',
        scheduledAtUtc: DateTime.utc(2026, 8, 24, 6),
        kind: 'appointment',
        status: 'missed',
      ),
    ], nowUtc: now);

    expect(result, hasLength(2));
    expect(result[0].occurrenceId, 'latest');
    expect(result[0].patientName, 'مامان جون');
    expect(result[1].occurrenceId, 'visit');
  });

  test('ignores future, completed, and scheduled items', () {
    final now = DateTime.utc(2026, 8, 24, 9);
    final result = selectLatestMissedAlertPerPatient([
      CareRecipientAlert(
        patientUserId: 'p1',
        patientName: 'مامان',
        occurrenceId: 'future',
        title: 'دارو',
        scheduledAtUtc: DateTime.utc(2026, 8, 24, 10),
        kind: 'medication',
        status: 'missed',
      ),
      CareRecipientAlert(
        patientUserId: 'p1',
        patientName: 'مامان',
        occurrenceId: 'done',
        title: 'دارو',
        scheduledAtUtc: DateTime.utc(2026, 8, 24, 8),
        kind: 'medication',
        status: 'taken',
      ),
      CareRecipientAlert(
        patientUserId: 'p1',
        patientName: 'مامان',
        occurrenceId: 'scheduled',
        title: 'دارو',
        scheduledAtUtc: DateTime.utc(2026, 8, 24, 8),
        kind: 'medication',
        status: 'scheduled',
      ),
    ], nowUtc: now);

    expect(result, isEmpty);
  });
}
