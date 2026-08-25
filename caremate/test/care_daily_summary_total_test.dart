import 'package:caremate/models/care_daily_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('summary total remains the authoritative fetched item count', () {
    const summary = CareDailySummary(
      patientUserId: 'patient-a',
      patientDisplayName: 'Mom',
      total: 5,
      completed: 3,
      pending: 1,
      alerts: 1,
    );
    expect(summary.total, 5);
    expect(summary.completed + summary.unresolved, 5);
  });
}
