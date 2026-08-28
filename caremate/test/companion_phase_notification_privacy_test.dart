import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

import '../lib/providers/companion_phase_notification_provider.dart';

void main() {
  const candidate = LifeMateCompanionPhaseNotification(
    guidanceId: 'notify.phase.period_start.2026-08-28',
    contentVersion: 'companion-phase-notifications-v1',
    title: 'A gentle moment to support',
    fullBody: 'A period start was recorded.',
    privateBody: 'You have a private CareMate update. Open the app for details.',
    isPrediction: false,
  );

  test('full lock screen may use approved scoped copy', () {
    final presentation = companionPhaseNotificationPresentation(candidate, 'full');
    expect(presentation.title, candidate.title);
    expect(presentation.body, candidate.fullBody);
    expect(presentation.visibility, NotificationVisibility.public);
  });

  test('limited lock screen hides cycle detail', () {
    final presentation = companionPhaseNotificationPresentation(candidate, 'limited');
    expect(presentation.title, 'CareMate');
    expect(presentation.body, candidate.privateBody);
    expect(presentation.body.toLowerCase(), isNot(contains('period')));
    expect(presentation.visibility, NotificationVisibility.private);
  });

  test('hidden lock screen uses secret visibility and private copy', () {
    final presentation = companionPhaseNotificationPresentation(candidate, 'hidden');
    expect(presentation.title, 'CareMate');
    expect(presentation.body, candidate.privateBody);
    expect(presentation.visibility, NotificationVisibility.secret);
  });
}
