import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../core/utils/string_extensions.dart';
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

  Future<void> syncReminders(
    List<ScheduleItemModel> items, {
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
      if (request.payload?.startsWith('lifemate-reminder:') == true ||
          request.payload?.startsWith('dose:') == true) {
        await _notifications.cancel(request.id);
      }
    }

    final nowUtc = DateTime.now().toUtc();
    for (final item in items) {
      final scheduledUtc = _scheduledUtc(item);
      if (scheduledUtc == null ||
          !scheduledUtc.isAfter(nowUtc) ||
          item.status != 'scheduled') {
        continue;
      }
      final triggerUtc = scheduledUtc.subtract(
        Duration(minutes: item.patientReminderMinutesBefore),
      );
      if (!triggerUtc.isAfter(nowUtc)) continue;

      final notificationId = _notificationId('${item.type}:${item.id}');
      await _notifications.cancel(notificationId);
      final title = _title(item, isPersian);
      final detail = _detail(item, isPersian);
      await _notifications.zonedSchedule(
        notificationId,
        title.toPersianDigit(isPersian),
        detail.toPersianDigit(isPersian),
        tz.TZDateTime.from(triggerUtc, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'wellmate_treatment_reminders',
            'یادآور برنامه درمان و مراقبت',
            channelDescription: 'یادآورهای دارو، ویزیت و تزریق WellMate',
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.reminder,
            visibility: NotificationVisibility.private,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: 'lifemate-reminder:${item.type}:${item.id}',
      );
    }
  }

  DateTime? _scheduledUtc(ScheduleItemModel item) {
    if (item.scheduledAtUtc != null) return item.scheduledAtUtc!.toUtc();
    final date = item.startDate;
    final parts = item.time.split(':');
    if (date == null || parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1].split(' ').first);
    if (hour == null || minute == null) return null;
    return tz.TZDateTime(
      tz.local,
      date.year,
      date.month,
      date.day,
      hour,
      minute,
    ).toUtc();
  }

  static String _title(ScheduleItemModel item, bool persian) {
    if (!persian) {
      return switch (item.type) {
        'appointment' => 'Upcoming appointment',
        'injection' => 'Upcoming injection',
        _ => 'Time for ${item.title}',
      };
    }
    return switch (item.type) {
      'appointment' => 'یادآوری ویزیت ${item.title}',
      'injection' => 'یادآوری تزریق ${item.title}',
      _ => 'زمان مصرف ${item.title}',
    };
  }

  static String _detail(ScheduleItemModel item, bool persian) {
    final lead = item.patientReminderMinutesBefore;
    final leadText = lead <= 0
        ? (persian ? 'اکنون' : 'now')
        : (persian ? '$lead دقیقه پیش از برنامه' : '$lead minutes before');
    final detail = item.dosage.trim();
    if (detail.isEmpty) return leadText;
    return '$detail — $leadText';
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
