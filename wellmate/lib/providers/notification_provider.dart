import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/schedule_item_model.dart';

class NotificationProvider extends ChangeNotifier {
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _hasUnread = false;
  bool _initialized = false;
  bool _permissionRequested = false;

  bool get hasUnread => _hasUnread;

  Future<void> initialize() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _notifications.initialize(
      settings,
      onDidReceiveNotificationResponse: (_) => setUnread(true),
    );
    _initialized = true;
  }

  Future<void> syncDoseReminders(
    List<ScheduleItemModel> doses, {
    required String timeZone,
  }) async {
    await initialize();
    try {
      tz.setLocalLocation(tz.getLocation(timeZone));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Asia/Tehran'));
    }

    if (!_permissionRequested) {
      final android = _notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
      await android?.requestExactAlarmsPermission();
      _permissionRequested = true;
    }

    for (final dose in doses) {
      final notificationId = _notificationId(dose.id);
      await _notifications.cancel(notificationId);
      final utc = dose.scheduledAtUtc;
      if (utc == null ||
          !utc.isAfter(DateTime.now().toUtc()) ||
          dose.status != 'scheduled') {
        continue;
      }

      await _notifications.zonedSchedule(
        notificationId,
        'زمان مصرف ${dose.title}',
        dose.dosage.isEmpty
            ? 'برای ثبت مصرف، WellMate را باز کنید.'
            : '${dose.dosage} — پس از مصرف در WellMate ثبت کنید.',
        tz.TZDateTime.from(utc, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'wellmate_dose_reminders',
            'یادآور مصرف دارو',
            channelDescription: 'یادآورهای برنامه درمانی WellMate',
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.reminder,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: 'dose:${dose.id}',
      );
    }
  }

  static int _notificationId(String value) {
    var hash = 0x811c9dc5;
    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }

  void setUnread(bool value) {
    _hasUnread = value;
    notifyListeners();
  }
}
