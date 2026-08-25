import 'package:caremate/models/care_daily_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('summary identity remains person-scoped', () {
    const first = CareDailySummary(
      patientUserId: 'patient-a',
      patientDisplayName: 'Mom',
      total: 1,
      completed: 1,
      pending: 0,
      alerts: 0,
    );
    const second = CareDailySummary(
      patientUserId: 'patient-b',
      patientDisplayName: 'Dad',
      total: 1,
      completed: 0,
      pending: 1,
      alerts: 0,
    );

    expect(first.patientUserId, isNot(second.patientUserId));
    expect(first.patientDisplayName, 'Mom');
    expect(second.patientDisplayName, 'Dad');
  });
}
