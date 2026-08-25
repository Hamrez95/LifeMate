import 'package:caremate/models/care_daily_summary.dart';
import 'package:caremate/providers/care_notification_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Persian summary copy names the correct person and recorded counts', () {
    const summary = CareDailySummary(
      patientUserId: 'patient-a',
      patientDisplayName: 'مامان',
      total: 3,
      completed: 2,
      pending: 1,
      alerts: 0,
    );

    final copy = CareNotificationProvider.dailySummaryCopy(
      summary,
      isPersian: true,
    );

    expect(copy.title, contains('مامان'));
    expect(copy.body, contains('2 از 3'));
    expect(copy.body, contains('1 مورد'));
  });
}
