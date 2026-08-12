import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../core/utils/string_extensions.dart';
import '../models/care_recipient_reminder.dart';
import 'package:lifemate_client/lifemate_client.dart';

class CareNotificationProvider extends ChangeNotifier {
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
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

    if (!_permissionRequested) {
      final android = _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await android?.requestNotificationsPermission();
      await android?.requestExactAlarmsPermission();
      _permissionRequested = true;
    }

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
        _notificationId(reminder.patientUserId),
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

  static int _notificationId(String value) {
    var hash = 0x811c9dc5;
    for (final codeUnit in 'care:$value'.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }
}
