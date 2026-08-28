import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

import '../lib/providers/companion_phase_notification_provider.dart';

void main() {
  const candidate = LifeMateCompanionFertilityNotification(
    guidanceId: 'notify.fertility.window.2026-08-15',
    contentVersion: 'companion-fertility-notifications-v1',
    title: 'Estimated fertility window',
    fullBody: 'Based on recorded cycle information, this is an estimated window.',
    privateBody: 'You have a private CareMate update. Open the app for details.',
  );

  test('full lock screen may show the explicitly consented estimate', () {
    final value = companionFertilityNotificationPresentation(candidate, 'full');
    expect(value.visibility, NotificationVisibility.public);
    expect(value.title, contains('Estimated'));
    expect(value.body, contains('estimated'));
  });

  test('limited lock screen strips fertility detail', () {
    final value = companionFertilityNotificationPresentation(candidate, 'limited');
    expect(value.visibility, NotificationVisibility.private);
    expect(value.title, 'CareMate');
    expect(value.body.toLowerCase(), isNot(contains('fertility')));
    expect(value.body.toLowerCase(), isNot(contains('ovulation')));
  });

  test('hidden lock screen remains secret and generic', () {
    final value = companionFertilityNotificationPresentation(candidate, 'hidden');
    expect(value.visibility, NotificationVisibility.secret);
    expect(value.title, 'CareMate');
    expect(value.body.toLowerCase(), isNot(contains('fertility')));
  });
}
