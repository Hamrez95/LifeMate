import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:lifemate_core/lifemate_reminders.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'women_insight_preferences_api.dart';

class WomenScheduledCycleInsight {
  const WomenScheduledCycleInsight({
    required this.insightId,
    required this.insightType,
    required this.analyticsKey,
  });

  final String insightId;
  final String insightType;
  final String analyticsKey;
}

/// Local-only, privacy-minimized Cycle Insight delivery.
///
/// This service intentionally does not initialize the notifications plugin and
/// never requests OS permission. WellMate's canonical NotificationProvider is
/// initialized at app startup and remains the sole notification-response owner.
/// Cycle Insight uses the shared LifeMate local reminder execution engine and
/// keeps notification text free of symptom, pain, note, fertility and raw
/// cycle-date data.
class WomenCycleInsightNotificationScheduler {
  WomenCycleInsightNotificationScheduler({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  late final LifeMateLocalReminderScheduler _scheduler =
      LifeMateLocalReminderScheduler(
        platform: FlutterLifeMateReminderPlatform(_plugin),
      );

  static const _channelId = 'women_cycle_insights';
  static const _payloadPrefix = 'women-health:cycle-insight';

  Future<List<WomenScheduledCycleInsight>> sync({
    required Map<String, dynamic> profile,
    required bool isPersian,
  }) async {
    final scheduled = <WomenScheduledCycleInsight>[];
    final preferences =
        profile['insightPreferences'] as Map<String, dynamic>? ?? const {};
    final insightsEnabled = preferences['insightsEnabled'] != false;
    final notificationsEnabled = preferences['notificationsEnabled'] == true;

    if (!insightsEnabled || !notificationsEnabled) {
      await cancelAll();
      return scheduled;
    }

    if (defaultTargetPlatform != TargetPlatform.android) {
      return scheduled;
    }
    final android = _plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin
    >();
    final enabled = await android?.areNotificationsEnabled() ?? false;
    if (!enabled) {
      await cancelAll();
      return scheduled;
    }

    tz_data.initializeTimeZones();
    final timeZone = profile['timeZone']?.toString().trim().isNotEmpty == true
        ? profile['timeZone'].toString().trim()
        : 'Asia/Tehran';
    final location = _locationFor(timeZone);
    final reminders = <LifeMateLocalReminder>[];

    if (preferences['expectedPeriodNotifications'] != false) {
      final trigger = _nextExpectedPeriodTrigger(profile, location);
      if (trigger != null) {
        reminders.add(
          _reminder(
            sourceKey: 'women-cycle:expected-period',
            triggerUtc: trigger,
            title: isPersian ? 'یادآوری Women Health' : 'Women Health reminder',
            body: isPersian
                ? 'برای مرور تقویم، LifeMate را باز کنید.'
                : 'Open LifeMate to review your calendar.',
            payload: '$_payloadPrefix:expected-period',
          ),
        );
        scheduled.add(
          const WomenScheduledCycleInsight(
            insightId: 'local.expected_period_window',
            insightType: 'expected_period_window',
            analyticsKey: 'cycle_insight.expected_period.local_scheduled',
          ),
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
      final trigger = _nextLocalHourUtc(
        location: location,
        hour: 19,
        afterDays: intervalDays,
      );
      reminders.add(
        _reminder(
          sourceKey: 'women-cycle:logging-reminder',
          triggerUtc: trigger,
          title: isPersian ? 'یادآوری LifeMate' : 'LifeMate reminder',
          body: isPersian
              ? 'اگر خواستی، LifeMate را باز کن و حال امروزت را ثبت کن.'
              : 'Open LifeMate if you want to log how you feel today.',
          payload: '$_payloadPrefix:logging-reminder',
        ),
      );
      scheduled.add(
        const WomenScheduledCycleInsight(
          insightId: 'local.logging_reminder',
          insightType: 'logging_reminder',
          analyticsKey: 'cycle_insight.logging_reminder.local_scheduled',
        ),
      );
    }

    await _scheduler.sync(
      reminders: reminders,
      timeZone: timeZone,
      ownsPendingRequest: _ownsCycleInsightRequest,
    );
    await _recordScheduled(scheduled);
    return scheduled;
  }

  Future<void> cancelAll() => _scheduler.sync(
    reminders: const <LifeMateLocalReminder>[],
    timeZone: 'UTC',
    ownsPendingRequest: _ownsCycleInsightRequest,
  );

  LifeMateLocalReminder _reminder({
    required String sourceKey,
    required DateTime triggerUtc,
    required String title,
    required String body,
    required String payload,
  }) => LifeMateLocalReminder(
    sourceOccurrenceKey: sourceKey,
    sourceRevision: LifeMateReminderIdentity.stableRevisionFor(
      '$sourceKey|${triggerUtc.toUtc().toIso8601String()}',
    ),
    triggerUtc: triggerUtc,
    title: title,
    body: body,
    notificationDetails: const NotificationDetails(
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
    payload: payload,
    accuracy: LifeMateReminderAccuracy.inexact,
  );

  static bool _ownsCycleInsightRequest(PendingNotificationRequest request) =>
      request.payload?.startsWith(_payloadPrefix) == true;

  Future<void> _recordScheduled(List<WomenScheduledCycleInsight> values) async {
    if (values.isEmpty) return;
    final api = WomenInsightPreferencesApi.fromEnvironment();
    try {
      for (final value in values) {
        try {
          await api.recordDelivery(
            insightId: value.insightId,
            insightType: value.insightType,
            surface: 'local_notification',
            analyticsKey: value.analyticsKey,
          );
        } catch (_) {
          debugPrint('Cycle Insight delivery metadata recording failed safely.');
        }
      }
    } finally {
      api.close();
    }
  }

  DateTime? _nextExpectedPeriodTrigger(
    Map<String, dynamic> profile,
    tz.Location location,
  ) {
    final lastStart = DateTime.tryParse(
      profile['lastPeriodStart']?.toString() ?? '',
    );
    final cycleLength = profile['cycleLength'] is int
        ? profile['cycleLength'] as int
        : int.tryParse(profile['cycleLength']?.toString() ?? '');
    if (lastStart == null ||
        cycleLength == null ||
        cycleLength < 21 ||
        cycleLength > 45) {
      return null;
    }
    final now = tz.TZDateTime.now(location);
    var expected = tz.TZDateTime(
      location,
      lastStart.year,
      lastStart.month,
      lastStart.day,
    ).add(Duration(days: cycleLength));
    var guard = 0;
    while (!expected.isAfter(now) && guard < 18) {
      expected = expected.add(Duration(days: cycleLength));
      guard += 1;
    }
    if (!expected.isAfter(now)) return null;
    final localTrigger = tz.TZDateTime(
      location,
      expected.year,
      expected.month,
      expected.day,
      10,
    ).subtract(const Duration(days: 1));
    if (localTrigger.isAfter(now)) return localTrigger.toUtc();
    final fallback = now.add(const Duration(hours: 2));
    return fallback.isBefore(expected) ? fallback.toUtc() : null;
  }

  DateTime _nextLocalHourUtc({
    required tz.Location location,
    required int hour,
    required int afterDays,
  }) {
    final now = tz.TZDateTime.now(location);
    var value = tz.TZDateTime(
      location,
      now.year,
      now.month,
      now.day,
      hour,
    ).add(Duration(days: afterDays));
    if (!value.isAfter(now)) value = value.add(const Duration(days: 1));
    return value.toUtc();
  }

  static tz.Location _locationFor(String timeZone) {
    try {
      return tz.getLocation(timeZone);
    } catch (_) {
      return tz.UTC;
    }
  }
}
