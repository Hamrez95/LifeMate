import 'package:caremate/models/care_daily_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('unresolved is pending plus missed or skipped alerts', () {
    const summary = CareDailySummary(
      patientUserId: 'patient-a',
      patientDisplayName: 'Mom',
      total: 4,
      completed: 1,
      pending: 2,
      alerts: 1,
    );

    expect(summary.unresolved, 3);
  });
}
