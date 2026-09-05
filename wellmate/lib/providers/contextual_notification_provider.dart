import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:lifemate_client/lifemate_client.dart';

import '../models/schedule_item_model.dart';
import 'care_event_projection_sync_bridge.dart';
import 'notification_provider.dart';
import 'pending_treatment_create_reminder_lifecycle.dart';
import 'pending_treatment_create_reminder_sync.dart';
import 'treatment_reconnect_sync_bridge.dart';
import 'treatment_reminder_reconciler.dart';

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
  LifeMateApiClient? _apiClient;
  bool _projectionSyncInFlight = false;
  bool _durableReconnectInFlight = false;

  bool get nativePermissionFlowUnlocked => _nativePermissionFlowUnlocked;

  @override
  void attachApiClient(LifeMateApiClient apiClient) {
    super.attachApiClient(apiClient);
    _apiClient = apiClient;
    if (_nativePermissionFlowUnlocked) {
      unawaited(_syncDurableProjections());
    }
  }

  @override
  void detachApiClient(LifeMateApiClient apiClient) {
    super.detachApiClient(apiClient);
    if (identical(_apiClient, apiClient)) {
      _apiClient = null;
    }
  }

  @override
  Future<void> syncReminders(
    List<ScheduleItemModel> items, {
    required String timeZone,
    required bool isPersian,
    Set<String>? affectedMedicationOccurrenceIds,
  }) async {
    _latestItems = List<ScheduleItemModel>.unmodifiable(items);
    _latestTimeZone = timeZone;
    _latestIsPersian = isPersian;

    if (!_permissionCheckCompleted) {
      await refreshExistingPermission();
    }
    if (!_nativePermissionFlowUnlocked) return;

    await super.syncReminders(
      items,
      timeZone: timeZone,
      isPersian: isPersian,
      affectedMedicationOccurrenceIds: affectedMedicationOccurrenceIds,
    );
    unawaited(_syncDurableProjections());
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
    unawaited(_syncDurableProjections());
    return WellMateNotificationPermissionResult.granted;
  }

  Future<void> _syncDurableProjections() async {
    final api = _apiClient;
    if (api == null ||
        !_nativePermissionFlowUnlocked ||
        _durableReconnectInFlight) {
      return;
    }
    _durableReconnectInFlight = true;
    try {
      await reconcilePendingTreatmentReminderLifecycle(
        syncPending: () => _syncPendingTreatmentCreateReminders(api),
        reconnect: () => _syncTreatmentAfterReconnect(api),
      );
      await _syncCareEventProjections();
    } finally {
      _durableReconnectInFlight = false;
    }
  }

  /// Projects durable pending treatment creates through the same shared #830
  /// scheduler instance used by canonical WellMate reminders. The protected
  /// outbox remains the only input; no server IDs are invented and the pending
  /// payload has no adherence actions. An empty projection intentionally
  /// cancels only this provisional namespace after clean authoritative replay.
  Future<void> _syncPendingTreatmentCreateReminders(LifeMateApiClient api) async {
    if (api is! DurableLifeMateApiClient) return;
    try {
      final pendingCreates = await api.pendingOfflineTreatmentPlanCreates();
      await PendingTreatmentCreateReminderSync(
        scheduler: sharedReminderScheduler,
      ).sync(
        pendingCreates: pendingCreates,
        nowUtc: DateTime.now().toUtc(),
        schedulingTimeZone: _latestTimeZone,
        isPersian: _latestIsPersian,
        exactAlarmGranted: sharedExactAlarmGranted,
      );
    } catch (_) {
      // Fail closed without logging PHI/outbox payloads. The next app/reminder
      // refresh retries from the same protected Person-scoped runtime.
    }
  }

  /// Replays accepted local treatment mutations before pulling authoritative
  /// treatment truth. The durable client invokes the callback only when replay
  /// is clean: conflict, terminal rejection, retry retention, pending work, or
  /// an offline cached Home fallback all keep the existing reminder window.
  Future<LifeMateTreatmentReconnectResult?> _syncTreatmentAfterReconnect(
    LifeMateApiClient api,
  ) async {
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, now.day);
    final to = from.add(const Duration(days: 7));
    try {
      return await reconcileOwnerTreatmentAfterReconnectIfSupported(
        apiClient: api,
        fromDate: from,
        toDate: to,
        reconcileReminders: (serverSnapshot) async {
          final next = reconcileTreatmentReminderWindow(
            currentItems: _latestItems,
            serverSnapshot: serverSnapshot,
            now: DateTime.now(),
          );
          final affectedOccurrenceIds = changedTreatmentReminderOccurrenceIds(
            currentItems: _latestItems,
            nextItems: next,
          );

          // Reconcile only changed medication occurrences and the minimum
          // grouped-reminder neighbors they depend on. Unrelated medication and
          // care reminders remain OS-owned and are not cancelled/recreated.
          if (affectedOccurrenceIds.isNotEmpty) {
            await super.syncReminders(
              next,
              timeZone: _latestTimeZone,
              isPersian: _latestIsPersian,
              affectedMedicationOccurrenceIds: affectedOccurrenceIds,
            );
          }
          _latestItems = List<ScheduleItemModel>.unmodifiable(next);
        },
      );
    } catch (_) {
      // Fail closed and stay quiet. Durable replay/conflict state remains the
      // source of truth and no PHI/server error text is written to logs here.
      return null;
    }
  }

  /// Pulls owner care-event changes through the durable shared runtime. The
  /// pre-checkpoint callback refreshes the currently scheduled WellMate window
  /// before the encrypted cursor can advance. If reminder reconciliation fails,
  /// the projection runtime deliberately retains the previous cursor so the
  /// same page can be replayed after reconnect/restart.
  Future<void> _syncCareEventProjections() async {
    final api = _apiClient;
    if (api == null ||
        !_nativePermissionFlowUnlocked ||
        _latestItems.isEmpty ||
        _projectionSyncInFlight) {
      return;
    }
    _projectionSyncInFlight = true;
    try {
      await syncOwnerCareEventProjectionsIfSupported(
        apiClient: api,
        beforeCheckpoint: (affectedRecordKeys) =>
            _reconcileAffectedCareEvents(api, affectedRecordKeys),
      );
    } catch (_) {
      // Fail closed and stay quiet: the durable projection cursor remains at
      // the previous checkpoint and will be retried by the next successful
      // reminder/app refresh. Never include PHI or server text in logs here.
    } finally {
      _projectionSyncInFlight = false;
    }
  }

  Future<void> _reconcileAffectedCareEvents(
    LifeMateApiClient api,
    Set<String> affectedRecordKeys,
  ) async {
    final affected = affectedRecordKeys
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    if (affected.isEmpty) return;
    if (_latestItems.isEmpty) {
      throw StateError('WellMate reminder snapshot is not initialized.');
    }

    final now = DateTime.now();
    final from = DateTime(now.year, now.month, now.day);
    final to = from.add(const Duration(days: 7));
    final freshEvents = await api.getCareEvents(fromDate: from, toDate: to);
    final refreshedAffected = freshEvents
        .where((event) => affected.contains(_seriesKey(event)))
        .map(_careEventItemFromApi)
        .where((item) => item.id.isNotEmpty && item.status == 'scheduled')
        .toList(growable: false);

    final next = <ScheduleItemModel>[
      for (final item in _latestItems)
        if (item.type == 'medicine' ||
            !affected.contains((item.seriesId ?? item.id).trim()))
          item,
      ...refreshedAffected,
    ];

    // Reuse the one shared #830 scheduler already owned by NotificationProvider.
    // The list remains complete for the active reminder window, preventing this
    // targeted care-event refresh from cancelling unrelated medication/care
    // reminders while still removing cancelled/moved affected occurrences.
    await super.syncReminders(
      next,
      timeZone: _latestTimeZone,
      isPersian: _latestIsPersian,
    );
    _latestItems = List<ScheduleItemModel>.unmodifiable(next);
  }

  static String _seriesKey(Map<String, dynamic> event) {
    final seriesId = event['seriesId']?.toString().trim();
    if (seriesId != null && seriesId.isNotEmpty) return seriesId;
    return event['id']?.toString().trim() ?? '';
  }

  static ScheduleItemModel _careEventItemFromApi(Map<String, dynamic> event) {
    final eventType = event['eventType']?.toString().toLowerCase();
    final type = eventType == 'injection' ? 'injection' : 'appointment';
    final rawTime = event['scheduledLocalTime']?.toString() ?? '';
    final status = event['status']?.toString().toLowerCase() ?? 'scheduled';
    return ScheduleItemModel(
      id: event['id']?.toString() ?? '',
      seriesId: event['seriesId']?.toString(),
      type: type,
      title: event['title']?.toString().trim().isNotEmpty == true
          ? event['title'].toString()
          : type == 'injection'
          ? 'Injection'
          : 'Appointment',
      time: rawTime.length >= 5 ? rawTime.substring(0, 5) : rawTime,
      dosage: '',
      status: status,
      version: event['version'] is int
          ? event['version'] as int
          : int.tryParse(event['version']?.toString() ?? '') ?? 1,
      scheduledAtUtc: DateTime.tryParse(
        event['scheduledAtUtc']?.toString() ?? '',
      )?.toUtc(),
      isDone: status == 'completed' || status == 'cancelled',
      frequency: type == 'injection' ? 'Injection' : 'Appointment',
      startDate: DateTime.tryParse(
        event['scheduledLocalDate']?.toString() ?? '',
      ),
      intervalDays: 1,
      patientReminderMinutesBefore: LifeMateReminderLeadTimes.normalize(
        event['patientReminderMinutesBefore'],
        fallback: LifeMateReminderLeadTimes.defaultPatientMinutes,
      ),
      caregiverReminderMinutesBefore: LifeMateReminderLeadTimes.normalize(
        event['caregiverReminderMinutesBefore'],
        fallback: LifeMateReminderLeadTimes.defaultCaregiverMinutes,
      ),
    );
  }
}
