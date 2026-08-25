import 'package:caremate/providers/care_notification_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('invalid preferred time fails closed', () {
    expect(
      CareNotificationProvider.isDailySummaryDue(
        DateTime(2026, 8, 25, 22),
        '25:99',
      ),
      isFalse,
    );
  });
}
