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

  test('WellMate owner reminders use shared offline scheduling engine', () {
    final provider = File(
      'lib/providers/notification_provider.dart',
    ).readAsStringSync();

    expect(
      provider,
      contains("package:lifemate_core/lifemate_reminders.dart"),
    );
    expect(provider, contains('LifeMateLocalReminderScheduler'));
    expect(provider, contains('LifeMateLocalReminder('));
    expect(provider, contains('LifeMateReminderAccuracy.exact'));
    expect(provider, contains('requestNotificationsPermission()'));
    expect(provider, contains('requestExactAlarmsPermission()'));
    expect(provider, isNot(contains('_notifications.zonedSchedule(')));
    expect(provider, contains("_reminderPrefix = 'lifemate-reminder:'"));
    expect(provider, contains('payload: encodeActionPayload(target)'));
    expect(provider, contains('inexactFallbackActive'));
  });

  test('Women Health uses the same shared scheduler without a parallel engine', () {
    final source = File(
      'lib/screens/women_calendar/women_cycle_insight_notification_scheduler.dart',
    ).readAsStringSync();

    expect(
      source,
      contains("package:lifemate_core/lifemate_reminders.dart"),
    );
    expect(source, contains('LifeMateLocalReminderScheduler'));
    expect(source, contains('LifeMateReminderAccuracy.inexact'));
    expect(source, isNot(contains('.zonedSchedule(')));
    expect(source, contains('women-health:cycle-insight'));
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
