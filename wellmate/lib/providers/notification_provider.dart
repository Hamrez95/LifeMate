import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../core/state/wellmate_refresh.dart';
import '../core/utils/string_extensions.dart';
import '../models/schedule_item_model.dart';

class WellMateNotificationTarget {
  const WellMateNotificationTarget({
    required this.type,
    required this.id,
    required this.version,
    required this.clientRequestId,
    required this.isPersian,
    this.seriesId,
  });

  final String type;
  final String id;
  final String? seriesId;
  final int version;
  final String clientRequestId;
  final bool isPersian;

  bool get isMedicine => type == 'medicine';
  bool get isRecurringCareInstance =>
      !isMedicine && seriesId != null && seriesId!.isNotEmpty && seriesId != id;
  String get key => '$type:$id';

  Map<String, dynamic> toJson() => <String, dynamic>{
    'type': type,
    'id': id,
    if (seriesId != null && seriesId!.isNotEmpty) 'seriesId': seriesId,
    'version': version,
    'clientRequestId': clientRequestId,
    'isPersian': isPersian,
  };

  static WellMateNotificationTarget? fromJson(Map<String, dynamic> json) {
    final type = json['type']?.toString().trim() ?? '';
    final id = json['id']?.toString().trim() ?? '';
    final requestId = json['clientRequestId']?.toString().trim() ?? '';
    final version = int.tryParse(json['version']?.toString() ?? '');
    if (type.isEmpty || id.isEmpty || requestId.isEmpty || version == null) {
      return null;
    }
    return WellMateNotificationTarget(
      type: type,
      id: id,
      seriesId: json['seriesId']?.toString().trim(),
      version: version,
      clientRequestId: requestId,
      isPersian: json['isPersian'] == true,
    );
  }
}

class NotificationProvider extends ChangeNotifier {
  static const takenActionId = 'wellmate-taken';
  static const completedActionId = 'wellmate-completed';
  static const snoozeActionId = 'wellmate-snooze';
  static const openActionId = 'wellmate-open';
  static const _reminderPrefix = 'lifemate-reminder:';
  static const _snoozePrefix = 'lifemate-snooze:';
  static const _snoozeDuration = Duration(minutes: 10);

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  LifeMateApiClient? _apiClient;
  NotificationResponse? _pendingMutationResponse;
  bool _hasUnread = false;
  bool _initialized = false;
  bool _permissionRequested = false;

  bool get hasUnread => _hasUnread;

  void attachApiClient(LifeMateApiClient apiClient) {
    _apiClient = apiClient;
    final pending = _pendingMutationResponse;
    if (pending != null) {
      _pendingMutationResponse = null;
      unawaited(_handleNotificationResponse(pending));
    }
  }

  void detachApiClient(LifeMateApiClient apiClient) {
    if (identical(_apiClient, apiClient)) _apiClient = null;
  }

  Future<void> initialize() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _notifications.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );
    _initialized = true;
  }

  void _onNotificationResponse(NotificationResponse response) {
    final actionId = response.actionId;
    if ((actionId == takenActionId || actionId == completedActionId) &&
        _apiClient == null) {
      _pendingMutationResponse = response;
      return;
    }
    unawaited(_handleNotificationResponse(response));
  }

  Future<void> _handleNotificationResponse(NotificationResponse response) async {
    final target = decodeActionPayload(response.payload);
    if (target == null) {
      setUnread(true);
      return;
    }

    switch (response.actionId) {
      case takenActionId:
        if (!target.isMedicine) return;
        final apiClient = _apiClient;
        if (apiClient == null) {
          _pendingMutationResponse = response;
          return;
        }
        try {
          await apiClient.reportDose(
            occurrenceId: target.id,
            clientRequestId: target.clientRequestId,
            version: target.version,
            status: 'taken',
            occurredAtUtc: DateTime.now().toUtc(),
          );
          await _notifications.cancel(notificationIdFor(target.key));
          WellMateRefreshSignal.notifyChanged();
          setUnread(true);
        } on LifeMateApiException catch (error) {
          debugPrint(
            'WellMate notification dose action failed safely: ${error.code}',
          );
          setUnread(true);
        } catch (error) {
          debugPrint(
            'WellMate notification dose action failed safely: $error',
          );
          setUnread(true);
        }
      case completedActionId:
        if (target.isMedicine || target.isRecurringCareInstance) return;
        if (_apiClient == null) {
          _pendingMutationResponse = response;
          return;
        }
        try {
          await LifeMateEditApi.fromEnvironment().updateCareEventStatus(
            eventId: target.id,
            status: 'completed',
            expectedVersion: target.version,
          );
          await _notifications.cancel(notificationIdFor(target.key));
          WellMateRefreshSignal.notifyChanged();
          setUnread(true);
        } on LifeMateApiException catch (error) {
          debugPrint(
            'WellMate notification care-event action failed safely: ${error.code}',
          );
          setUnread(true);
        } catch (error) {
          debugPrint(
            'WellMate notification care-event action failed safely: $error',
          );
          setUnread(true);
        }
      case snoozeActionId:
        await _scheduleSnooze(target);
        setUnread(true);
      case openActionId:
      default:
        setUnread(true);
    }
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

    final activeScheduledItems = <String, ScheduleItemModel>{
      for (final item in items)
        if (item.status == 'scheduled') '${item.type}:${item.id}': item,
    };
    final preservedSnoozeKeys = <String>{};
    final pending = await _notifications.pendingNotificationRequests();
    for (final request in pending) {
      final payload = request.payload;
      if (payload?.startsWith(_snoozePrefix) == true) {
        final target = decodeActionPayload(payload);
        if (target != null && activeScheduledItems.containsKey(target.key)) {
          preservedSnoozeKeys.add(target.key);
        } else {
          await _notifications.cancel(request.id);
        }
        continue;
      }
      if (payload?.startsWith(_reminderPrefix) == true ||
          payload?.startsWith('dose:') == true) {
        await _notifications.cancel(request.id);
      }
    }

    final nowUtc = DateTime.now().toUtc();
    for (final item in items) {
      final itemKey = '${item.type}:${item.id}';
      if (preservedSnoozeKeys.contains(itemKey)) continue;
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

      final target = WellMateNotificationTarget(
        type: item.type,
        id: item.id,
        seriesId: item.seriesId,
        version: item.version,
        clientRequestId: LifeMateApiClient.createClientRequestId(),
        isPersian: isPersian,
      );
      final notificationId = notificationIdFor(target.key);
      await _notifications.cancel(notificationId);
      final title = _title(item, isPersian);
      final detail = _detail(item, isPersian);
      await _notifications.zonedSchedule(
        notificationId,
        title.toPersianDigit(isPersian),
        detail.toPersianDigit(isPersian),
        tz.TZDateTime.from(triggerUtc, tz.local),
        NotificationDetails(
          android: _androidDetails(target),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: encodeActionPayload(target),
      );
    }
  }

  Future<void> _scheduleSnooze(WellMateNotificationTarget target) async {
    await initialize();
    final trigger = tz.TZDateTime.now(tz.local).add(_snoozeDuration);
    final title = target.isPersian ? 'یادآور WellMate' : 'WellMate reminder';
    final body = target.isPersian
        ? '۱۰ دقیقه بعد دوباره یادت می‌اندازیم.'
        : 'We will remind you again in 10 minutes.';
    await _notifications.zonedSchedule(
      notificationIdFor(target.key),
      title,
      body,
      trigger,
      NotificationDetails(android: _androidDetails(target)),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: encodeActionPayload(target, snoozed: true),
    );
  }

  static AndroidNotificationDetails _androidDetails(
    WellMateNotificationTarget target,
  ) => AndroidNotificationDetails(
    'wellmate_treatment_reminders',
    target.isPersian
        ? 'یادآور برنامه درمان و مراقبت'
        : 'Treatment and care reminders',
    channelDescription: target.isPersian
        ? 'یادآورهای دارو، ویزیت و تزریق WellMate'
        : 'WellMate medication, visit and injection reminders',
    importance: Importance.high,
    priority: Priority.high,
    category: AndroidNotificationCategory.reminder,
    visibility: NotificationVisibility.private,
    actions: actionButtonsForTarget(target),
  );

  static List<AndroidNotificationAction> actionButtonsForTarget(
    WellMateNotificationTarget target,
  ) {
    final actions = <AndroidNotificationAction>[];
    if (target.isMedicine) {
      actions.add(
        AndroidNotificationAction(
          takenActionId,
          target.isPersian ? 'مصرف کردم' : 'Taken',
          showsUserInterface: true,
          cancelNotification: true,
        ),
      );
    } else if (!target.isRecurringCareInstance) {
      actions.add(
        AndroidNotificationAction(
          completedActionId,
          target.isPersian ? 'انجام شد' : 'Done',
          showsUserInterface: true,
          cancelNotification: true,
        ),
      );
    }
    actions.addAll(<AndroidNotificationAction>[
      AndroidNotificationAction(
        snoozeActionId,
        target.isPersian ? '۱۰ دقیقه بعد' : '10 min later',
        showsUserInterface: true,
        cancelNotification: true,
      ),
      AndroidNotificationAction(
        openActionId,
        target.isPersian ? 'باز کردن' : 'Open',
        showsUserInterface: true,
        cancelNotification: false,
      ),
    ]);
    return actions;
  }

  static String encodeActionPayload(
    WellMateNotificationTarget target, {
    bool snoozed = false,
  }) {
    final encoded = base64Url.encode(utf8.encode(jsonEncode(target.toJson())));
    return '${snoozed ? _snoozePrefix : _reminderPrefix}$encoded';
  }

  static WellMateNotificationTarget? decodeActionPayload(String? payload) {
    if (payload == null ||
        (!payload.startsWith(_reminderPrefix) &&
            !payload.startsWith(_snoozePrefix))) {
      return null;
    }
    final prefix = payload.startsWith(_snoozePrefix)
        ? _snoozePrefix
        : _reminderPrefix;
    final encoded = payload.substring(prefix.length);
    if (encoded.isEmpty) return null;
    try {
      final decoded = jsonDecode(utf8.decode(base64Url.decode(encoded)));
      if (decoded is! Map) return null;
      return WellMateNotificationTarget.fromJson(
        Map<String, dynamic>.from(decoded),
      );
    } catch (_) {
      return null;
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

  static int notificationIdFor(String value) {
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
