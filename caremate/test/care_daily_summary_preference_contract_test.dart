import 'package:caremate/providers/care_notification_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('daily summary waits for the configured local time', () {
    expect(
      CareNotificationProvider.isDailySummaryDue(
        DateTime(2026, 8, 25, 7, 59),
        '08:00',
      ),
      isFalse,
    );
    expect(
      CareNotificationProvider.isDailySummaryDue(
        DateTime(2026, 8, 25, 8),
        '08:00',
      ),
      isTrue,
    );
  });
}
