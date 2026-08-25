import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android manifest keeps reboot and app-update reminder recovery', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(
      manifest,
      contains('android.permission.RECEIVE_BOOT_COMPLETED'),
      reason: 'Scheduled reminders must be restorable after device reboot.',
    );
    expect(
      manifest,
      contains('android.permission.SCHEDULE_EXACT_ALARM'),
      reason: 'Treatment reminders use exact alarms on supported Android versions.',
    );
    expect(
      manifest,
      contains(
        'com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver',
      ),
    );
    expect(
      manifest,
      contains(
        'com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver',
      ),
    );
    expect(manifest, contains('android.intent.action.BOOT_COMPLETED'));
    expect(manifest, contains('android.intent.action.MY_PACKAGE_REPLACED'));
  });

  test('notification provider keeps exact timezone-aware reminder scheduling', () {
    final provider = File(
      'lib/providers/notification_provider.dart',
    ).readAsStringSync();

    expect(provider, contains('tz_data.initializeTimeZones()'));
    expect(provider, contains('tz.setLocalLocation'));
    expect(provider, contains('requestNotificationsPermission()'));
    expect(provider, contains('requestExactAlarmsPermission()'));
    expect(provider, contains('_notifications.zonedSchedule('));
    expect(
      provider,
      contains('AndroidScheduleMode.exactAllowWhileIdle'),
      reason: 'Reminder scheduling must not silently regress to an inexact mode.',
    );
    expect(provider, contains("_reminderPrefix = 'lifemate-reminder:'"));
    expect(provider, contains('payload: encodeActionPayload(target)'));
  });

  test('foreground recovery re-fetches schedule after app resume', () {
    final home = File('lib/screens/home/home_screen.dart').readAsStringSync();
    final homeContent = File(
      'lib/screens/home/home_screen_content.dart',
    ).readAsStringSync();

    expect(home, contains('with WidgetsBindingObserver'));
    expect(home, contains('AppLifecycleState.resumed'));
    expect(home, contains('_scheduleFullRefresh(forceWomenState: true)'));
    expect(
      home,
      contains('_refreshDebounceDuration'),
      reason: 'Resume recovery must stay debounced to avoid request storms.',
    );
    expect(
      homeContent,
      contains('if (oldWidget.refreshToken != widget.refreshToken)'),
    );
    expect(homeContent, contains('_fetchScheduleFromBackend(background: true)'));
    expect(homeContent, contains('.syncReminders('));
  });
}
