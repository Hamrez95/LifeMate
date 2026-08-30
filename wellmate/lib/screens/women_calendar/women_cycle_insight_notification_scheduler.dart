import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Local-only, privacy-minimized Cycle Insight delivery.
///
/// This service intentionally does not initialize the notifications plugin and
/// never requests OS permission. WellMate's canonical NotificationProvider is
/// initialized at app startup and remains the sole notification-response owner.
/// Cycle Insight notifications use separate IDs/channel and contain no symptom,
/// pain, note, fertility or raw cycle-date payload.
class WomenCycleInsightNotificationScheduler {
  WomenCycleInsightNotificationScheduler({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  static const _expectedPeriodId = 60901;
  static const _loggingReminderId = 60902;
  static const _channelId = 'women_cycle_insights';

  Future<void> sync({
    required Map<String, dynamic> profile,
    required bool isPersian,
  }) async {
    final preferences =
        profile['insightPreferences'] as Map<String, dynamic>? ?? const {};
    final insightsEnabled = preferences['insightsEnabled'] != false;
    final notificationsEnabled = preferences['notificationsEnabled'] == true;

    if (!insightsEnabled || !notificationsEnabled) {
      await cancelAll();
      return;
    }

    if (defaultTargetPlatform != TargetPlatform.android) {
      // Current WellMate initialization is Android-only. Do not pretend a
      // delivery path exists on an unsupported platform.
      return;
    }
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final enabled = await android?.areNotificationsEnabled() ?? false;
    if (!enabled) {
      await cancelAll();
      return;
    }

    tz_data.initializeTimeZones();
    await _plugin.cancel(_expectedPeriodId);
    await _plugin.cancel(_loggingReminderId);

    if (preferences['expectedPeriodNotifications'] != false) {
      final trigger = _nextExpectedPeriodTrigger(profile);
      if (trigger != null) {
        await _schedule(
          id: _expectedPeriodId,
          triggerUtc: trigger,
          title: isPersian ? 'یادآوری Women Health' : 'Women Health reminder',
          body: isPersian
              ? 'بر اساس تاریخچه فعلی، دوره بعدی ممکن است نزدیک باشد.'
              : 'Based on your current history, your next period may be approaching.',
        );
      }
    }

    if (preferences['loggingReminderNotifications'] != false) {
      final mode = preferences['frequencyMode']?.toString() ?? 'balanced';
      final intervalDays = switch (mode) {
        'low' => 7,
        'high' => 1,
        _ => 3,
      };
      final trigger = _nextLocalHourUtc(hour: 19, afterDays: intervalDays);
      await _schedule(
        id: _loggingReminderId,
        triggerUtc: trigger,
        title: isPersian ? 'یک یادآوری آرام' : 'A gentle reminder',
        body: isPersian
            ? 'اگر خواستی، می‌توانی حال امروزت را در Women Health ثبت کنی.'
            : 'If you want, you can log how you feel today in Women Health.',
      );
    }
  }

  Future<void> cancelAll() async {
    await _plugin.cancel(_expectedPeriodId);
    await _plugin.cancel(_loggingReminderId);
  }

  Future<void> _schedule({
    required int id,
    required DateTime triggerUtc,
    required String title,
    required String body,
  }) async {
    if (!triggerUtc.isAfter(DateTime.now().toUtc())) return;
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(triggerUtc, tz.UTC),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Women Health insights',
          channelDescription: 'Private, optional Women Health cycle insights',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          category: AndroidNotificationCategory.reminder,
          visibility: NotificationVisibility.private,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: 'women-health:cycle-insight',
    );
  }

  DateTime? _nextExpectedPeriodTrigger(Map<String, dynamic> profile) {
    final lastStart =
        DateTime.tryParse(profile['lastPeriodStart']?.toString() ?? '');
    final cycleLength = profile['cycleLength'] is int
        ? profile['cycleLength'] as int
        : int.tryParse(profile['cycleLength']?.toString() ?? '');
    if (lastStart == null || cycleLength == null || cycleLength < 21 || cycleLength > 45) {
      return null;
    }
    final now = DateTime.now();
    var expected = DateTime(lastStart.year, lastStart.month, lastStart.day)
        .add(Duration(days: cycleLength));
    var guard = 0;
    while (!expected.isAfter(now) && guard < 18) {
      expected = expected.add(Duration(days: cycleLength));
      guard += 1;
    }
    if (!expected.isAfter(now)) return null;
    final localTrigger = DateTime(
      expected.year,
      expected.month,
      expected.day,
      10,
    ).subtract(const Duration(days: 1));
    if (localTrigger.isAfter(now)) return localTrigger.toUtc();
    final fallback = now.add(const Duration(hours: 2));
    return fallback.isBefore(expected) ? fallback.toUtc() : null;
  }

  DateTime _nextLocalHourUtc({required int hour, required int afterDays}) {
    final now = DateTime.now();
    var value = DateTime(now.year, now.month, now.day, hour)
        .add(Duration(days: afterDays));
    if (!value.isAfter(now)) value = value.add(const Duration(days: 1));
    return value.toUtc();
  }
}
