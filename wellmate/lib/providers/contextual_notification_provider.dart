import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/schedule_item_model.dart';
import 'notification_provider.dart';

enum WellMateNotificationPermissionResult { granted, denied, unsupported }

/// Prevents reminder synchronization from triggering an OS permission prompt
/// before the user has seen a contextual explanation.
///
/// Existing scheduling/deduplication stays in [NotificationProvider]; this
/// wrapper only controls when that provider is allowed to cross the native
/// permission boundary.
class ContextualNotificationProvider extends NotificationProvider {
  bool _nativePermissionFlowUnlocked = false;
  bool _permissionCheckCompleted = false;

  List<ScheduleItemModel> _latestItems = const <ScheduleItemModel>[];
  String _latestTimeZone = 'Asia/Tehran';
  bool _latestIsPersian = true;

  bool get nativePermissionFlowUnlocked => _nativePermissionFlowUnlocked;

  @override
  Future<void> syncReminders(
    List<ScheduleItemModel> items, {
    required String timeZone,
    required bool isPersian,
  }) async {
    _latestItems = List<ScheduleItemModel>.unmodifiable(items);
    _latestTimeZone = timeZone;
    _latestIsPersian = isPersian;

    if (!_permissionCheckCompleted) {
      await refreshExistingPermission();
    }
    if (!_nativePermissionFlowUnlocked) return;

    await super.syncReminders(items, timeZone: timeZone, isPersian: isPersian);
  }

  /// Reads current OS state without requesting anything. Already-authorized
  /// users keep reminder scheduling after an upgrade without seeing V3 prompts.
  Future<bool> refreshExistingPermission() async {
    _permissionCheckCompleted = true;
    if (defaultTargetPlatform != TargetPlatform.android) {
      _nativePermissionFlowUnlocked = true;
      return true;
    }
    final android = FlutterLocalNotificationsPlugin()
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final enabled = await android?.areNotificationsEnabled() ?? false;
    _nativePermissionFlowUnlocked = enabled;
    return enabled;
  }

  /// Call only after the V3 pre-permission explanation and an explicit user
  /// action. No account, treatment or server notification preference is changed.
  Future<WellMateNotificationPermissionResult> requestAfterExplanation() async {
    _permissionCheckCompleted = true;
    if (defaultTargetPlatform != TargetPlatform.android) {
      _nativePermissionFlowUnlocked = true;
      return WellMateNotificationPermissionResult.unsupported;
    }

    await initialize();
    final android = FlutterLocalNotificationsPlugin()
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) {
      return WellMateNotificationPermissionResult.unsupported;
    }

    final notificationsGranted =
        await android.requestNotificationsPermission() ?? false;
    if (!notificationsGranted) {
      _nativePermissionFlowUnlocked = false;
      return WellMateNotificationPermissionResult.denied;
    }

    // Exact-alarm access is requested only inside this explicit flow. A denial
    // no longer drops reminders: the shared scheduler records and uses the
    // inexact-while-idle fallback until exact access is restored.
    final exactAlarmGranted = await android.requestExactAlarmsPermission();
    recordNativePermissionResult(exactAlarmGranted: exactAlarmGranted);
    _nativePermissionFlowUnlocked = true;

    await super.syncReminders(
      _latestItems,
      timeZone: _latestTimeZone,
      isPersian: _latestIsPersian,
    );
    return WellMateNotificationPermissionResult.granted;
  }
}
