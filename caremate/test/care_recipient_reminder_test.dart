import 'package:caremate/models/care_recipient_reminder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('selects only earliest future medicine per care recipient', () {
    final now = DateTime.utc(2026, 8, 4, 10);
    final result = selectEarliestReminderPerPatient([
      CareRecipientReminder(
        patientUserId: 'p1',
        patientName: 'ریحانه',
        doseId: 'late-p1',
        medicationName: 'دارو دوم',
        doseText: '۱ قرص',
        scheduledAtUtc: DateTime.utc(2026, 8, 4, 18),
      ),
      CareRecipientReminder(
        patientUserId: 'p1',
        patientName: 'ریحانه',
        doseId: 'first-p1',
        medicationName: 'دارو اول',
        doseText: '۱ قرص',
        scheduledAtUtc: DateTime.utc(2026, 8, 4, 12),
      ),
      CareRecipientReminder(
        patientUserId: 'p2',
        patientName: 'مادر',
        doseId: 'first-p2',
        medicationName: 'متفورمین',
        doseText: '۵۰۰',
        scheduledAtUtc: DateTime.utc(2026, 8, 4, 11),
      ),
      CareRecipientReminder(
        patientUserId: 'p2',
        patientName: 'مادر',
        doseId: 'past-p2',
        medicationName: 'گذشته',
        doseText: '',
        scheduledAtUtc: DateTime.utc(2026, 8, 4, 9),
      ),
    ], nowUtc: now);

    expect(result, hasLength(2));
    expect(result[0].doseId, 'first-p2');
    expect(result[1].doseId, 'first-p1');
  });
}
