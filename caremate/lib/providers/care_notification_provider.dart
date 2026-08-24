import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../core/utils/string_extensions.dart';
import '../models/care_recipient_alert.dart';
import '../models/care_recipient_reminder.dart';
import 'package:lifemate_client/lifemate_client.dart';

class CareNotificationProvider extends ChangeNotifier {
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  final Map<String, String> _lastMissedOccurrenceByPatient = {};
  bool _initialized = false;
  bool _permissionRequested = false;

  Future<void> initialize() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _notifications.initialize(settings);
    _initialized = true;
  }

  Future<void> syncEarliestPerRecipient(
    Iterable<CareRecipientReminder> candidates, {
    required String timeZone,
    required bool isPersian,
  }) async {
    await initialize();
    try {
      tz.setLocalLocation(tz.getLocation(timeZone));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Asia/Tehran'));
    }

    await _requestPermissionsIfNeeded();
    final pending = await _notifications.pendingNotificationRequests();
    for (final request in pending) {
      if (request.payload?.startsWith('care-reminder:') == true ||
          request.payload?.startsWith('care-dose:') == true) {
        await _notifications.cancel(request.id);
      }
    }
    final reminders = selectEarliestReminderPerPatient(candidates);
    for (final reminder in reminders) {
      final localTime = tz.TZDateTime.from(reminder.scheduledAtUtc, tz.local);
      final triggerTime = tz.TZDateTime.from(reminder.triggerAtUtc, tz.local);
      final timeText =
          '${localTime.hour.toString().padLeft(2, '0')}:'
                  '${localTime.minute.toString().padLeft(2, '0')}'
              .toPersianDigit(isPersian);
      final title = isPersian
          ? '${_kindTitle(reminder.kind)} ${reminder.patientName.toPersianDigit(true)}'
          : '${reminder.patientName} upcoming ${reminder.kind}';
      final detail = [
        reminder.medicationName,
        if (reminder.doseText.trim().isNotEmpty) reminder.doseText.trim(),
        timeText,
      ].join(' • ').toPersianDigit(isPersian);

      await _notifications.zonedSchedule(
        _notificationId('reminder:${reminder.patientUserId}'),
        title,
        detail,
        triggerTime,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'caremate_next_treatment',
            LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'برنامه بعدی افراد تحت مراقبت',
                en: "Next program of people in care",
              ),
              en: "Next program of people in care",
            ),
            channelDescription: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'نزدیک‌ترین یادآور دارو، ویزیت یا تزریق هر فرد در CareMate',
                en: "The nearest reminder of anyone's medication, visit or injection in CareMate",
              ),
              en: "The nearest reminder of anyone's medication, visit or injection in CareMate",
            ),
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.reminder,
            visibility: NotificationVisibility.private,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload:
            'care-reminder:${reminder.patientUserId}:${reminder.kind}:${reminder.doseId}',
      );
    }
  }

  Future<void> syncMissedAlerts(
    Iterable<CareRecipientAlert> candidates, {
    required bool isPersian,
  }) async {
    await initialize();
    await _requestPermissionsIfNeeded();

    final nowUtc = DateTime.now().toUtc();
    final alerts = selectLatestMissedAlertPerPatient(
      candidates,
      nowUtc: nowUtc,
    );
    final activePatients = alerts.map((alert) => alert.patientUserId).toSet();
    final stalePatients = _lastMissedOccurrenceByPatient.keys
        .where((patientUserId) => !activePatients.contains(patientUserId))
        .toList(growable: false);
    for (final patientUserId in stalePatients) {
      await _notifications.cancel(_notificationId('missed:$patientUserId'));
      _lastMissedOccurrenceByPatient.remove(patientUserId);
    }

    for (final alert in alerts) {
      if (_lastMissedOccurrenceByPatient[alert.patientUserId] ==
          alert.occurrenceId) {
        continue;
      }
      final scheduled = alert.scheduledAtUtc.toLocal();
      final timeText =
          '${scheduled.hour.toString().padLeft(2, '0')}:'
                  '${scheduled.minute.toString().padLeft(2, '0')}'
              .toPersianDigit(isPersian);
      final lateText = _lateText(alert, nowUtc, isPersian: isPersian);
      final title = LifeMateRuntimeLocale.select(
        fa: '${alert.patientName.toPersianDigit(true)} هنوز ${_missedVerb(alert.kind)}',
        en: '${alert.patientName} has an unfinished ${_kindLabel(alert.kind)}',
      );
      final detail = [
        alert.title,
        if (alert.subtitle.trim().isNotEmpty) alert.subtitle.trim(),
        LifeMateRuntimeLocale.select(
          fa: 'زمان برنامه: $timeText',
          en: 'Scheduled: $timeText',
        ),
        lateText,
      ].join(' • ').toPersianDigit(isPersian);

      await _notifications.show(
        _notificationId('missed:${alert.patientUserId}'),
        title,
        detail,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'caremate_missed_treatment',
            LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'هشدار درمان پیگیری‌نشده',
                en: 'Unfinished treatment alerts',
              ),
              en: 'Unfinished treatment alerts',
            ),
            channelDescription: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'هشدارهای شخص‌محور برای درمان‌های فراموش‌شده یا انجام‌نشده',
                en: 'Person-aware alerts for missed or unfinished treatment items',
              ),
              en: 'Person-aware alerts for missed or unfinished treatment items',
            ),
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.reminder,
            visibility: NotificationVisibility.private,
            onlyAlertOnce: true,
          ),
        ),
        payload:
            'care-missed:${alert.patientUserId}:${alert.kind}:${alert.occurrenceId}',
      );
      _lastMissedOccurrenceByPatient[alert.patientUserId] = alert.occurrenceId;
    }
  }

  Future<void> _requestPermissionsIfNeeded() async {
    if (_permissionRequested) return;
    final android = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.requestNotificationsPermission();
    await android?.requestExactAlarmsPermission();
    _permissionRequested = true;
  }

  static String _kindTitle(String kind) => switch (kind) {
    'appointment' => LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'ویزیت بعدی', en: "Next visit"),
      en: "Next visit",
    ),
    'injection' => LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'تزریق بعدی', en: "Next injection"),
      en: "Next injection",
    ),
    _ => LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'داروی بعدی', en: "Next medication"),
      en: "Next medication",
    ),
  };

  static String _missedVerb(String kind) => switch (kind) {
    'appointment' => LifeMateRuntimeLocale.select(
      fa: 'ویزیتش را انجام نداده',
      en: "hasn't completed the visit",
    ),
    'injection' => LifeMateRuntimeLocale.select(
      fa: 'تزریقش را انجام نداده',
      en: "hasn't completed the injection",
    ),
    _ => LifeMateRuntimeLocale.select(
      fa: 'دارویش را مصرف نکرده',
      en: "hasn't taken the medication",
    ),
  };

  static String _kindLabel(String kind) => switch (kind) {
    'appointment' => 'visit',
    'injection' => 'injection',
    _ => 'medication',
  };

  static String _lateText(
    CareRecipientAlert alert,
    DateTime nowUtc, {
    required bool isPersian,
  }) {
    final minutes = nowUtc.toUtc().difference(alert.scheduledAtUtc.toUtc()).inMinutes;
    if (minutes < 60) {
      return LifeMateRuntimeLocale.select(
        fa: '$minutes دقیقه گذشته',
        en: '$minutes min late',
      );
    }
    final hours = minutes ~/ 60;
    final remainder = minutes % 60;
    if (remainder == 0) {
      return LifeMateRuntimeLocale.select(
        fa: '$hours ساعت گذشته',
        en: '$hours h late',
      );
    }
    return LifeMateRuntimeLocale.select(
      fa: '$hours ساعت و $remainder دقیقه گذشته',
      en: '$hours h $remainder min late',
    );
  }

  static int _notificationId(String value) {
    var hash = 0x811c9dc5;
    for (final codeUnit in 'care:$value'.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }
}
