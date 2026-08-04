import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../core/utils/string_extensions.dart';
import '../models/care_recipient_reminder.dart';

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
      if (request.payload?.startsWith('care-dose:') == true) {
        await _notifications.cancel(request.id);
      }
    }
    final reminders = selectEarliestReminderPerPatient(candidates);
    for (final reminder in reminders) {
      final localTime = tz.TZDateTime.from(reminder.scheduledAtUtc, tz.local);
      final timeText =
          '${localTime.hour.toString().padLeft(2, '0')}:'
                  '${localTime.minute.toString().padLeft(2, '0')}'
              .toPersianDigit(isPersian);
      final title = isPersian
          ? 'داروی بعدی ${reminder.patientName.toPersianDigit(true)}'
          : '${reminder.patientName} next medicine';
      final detail = [
        reminder.medicationName,
        if (reminder.doseText.trim().isNotEmpty) reminder.doseText.trim(),
        timeText,
      ].join(' • ').toPersianDigit(isPersian);

      await _notifications.zonedSchedule(
        _notificationId(reminder.patientUserId),
        title,
        detail,
        localTime,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'caremate_next_dose',
            'داروی بعدی افراد تحت مراقبت',
            channelDescription:
                'فقط نزدیک‌ترین داروی هر فرد تحت مراقبت در CareMate',
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.reminder,
            visibility: NotificationVisibility.private,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: 'care-dose:${reminder.patientUserId}:${reminder.doseId}',
      );
    }
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
