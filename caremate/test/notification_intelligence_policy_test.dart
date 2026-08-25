import 'package:caremate/models/care_recipient_alert.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final scheduled = DateTime.utc(2026, 8, 25, 10);

  test('caregiver escalation fails closed when relationship is revoked', () {
    final alert = CareRecipientAlert(
      patientUserId: 'patient-a',
      patientName: 'Mom',
      occurrenceId: 'dose-a',
      title: 'Medication',
      scheduledAtUtc: scheduled,
      kind: 'medicine',
      status: 'missed',
    );

    expect(
      alert
          .decision(
            scheduled.add(const Duration(hours: 1)),
            relationshipAuthorized: false,
          )
          .shouldNotify,
      isFalse,
    );
  });

  test('same caregiver occurrence keeps a stable escalation dedup key', () {
    final alert = CareRecipientAlert(
      patientUserId: 'patient-a',
      patientName: 'Mom',
      occurrenceId: 'dose-a',
      title: 'Medication',
      scheduledAtUtc: scheduled,
      kind: 'medicine',
      status: 'missed',
    );

    expect(
      alert.deduplicationKey,
      'caregiverEscalation:patient-a:dose-a',
    );
  });
}
