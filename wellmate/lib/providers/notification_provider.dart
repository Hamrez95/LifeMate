import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:lifemate_core/lifemate_reminders.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../core/state/wellmate_refresh.dart';
import '../core/utils/string_extensions.dart';
import '../models/schedule_item_model.dart';
import 'grouped_medication_notification.dart';

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
  String get sourceId => '$type:$id';
  String get key => LifeMateNotificationIntelligence.deduplicationKey(
    personId: 'self',
    sourceId: sourceId,
    stage: LifeMateNotificationStage.reminder,
  );

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
  static const groupOpenActionId = 'wellmate-group-open';
  static const _reminderPrefix = 'lifemate-reminder:';
  static const _snoozePrefix = 'lifemate-snooze:';
  static const _snoozeDuration = Duration(minutes: 10);

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  late final LifeMateLocalReminderScheduler _reminderScheduler =
      LifeMateLocalReminderScheduler(
        platform: FlutterLifeMateReminderPlatform(_notifications),
      );
  LifeMateApiClient? _apiClient;
  NotificationResponse? _pendingMutationResponse;
  GroupedMedicationNotificationTarget? _pendingGroupedMedicationTarget;
  bool _hasUnread = false;
  bool _initialized = false;
  bool _permissionRequested = false;
  bool? _exactAlarmGranted;
  bool _inexactFallbackActive = false;
  String _latestTimeZone = 'Asia/Tehran';

  bool get hasUnread => _hasUnread;
  bool get inexactFallbackActive => _inexactFallbackActive;
  GroupedMedicationNotificationTarget? get pendingGroupedMedicationTarget =>
      _pendingGroupedMedicationTarget;

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

  GroupedMedicationNotificationTarget? consumePendingGroupedMedicationTarget() {
    final value = _pendingGroupedMedicationTarget;
    _pendingGroupedMedicationTarget = null;
    return value;
  }

  Future<void> initialize() async {
    if (_initialized) return;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _notifications.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );
    _initialized = true;
  }

  @protected
  void recordNativePermissionResult({bool? exactAlarmGranted}) {
    _permissionRequested = true;
    _exactAlarmGranted = exactAlarmGranted;
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
    final grouped = decodeGroupedMedicationPayload(response.payload);
    if (grouped != null) {
      _pendingGroupedMedicationTarget = grouped;
      setUnread(true);
      return;
    }

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
          await _notifications.cancel(
            notificationIdFor(
              target.key,
              sourceRevision: target.version,
            ),
          );
          WellMateRefreshSignal.notifyChanged();
          setUnread(true);
        } on LifeMateApiException catch (error) {
          debugPrint(
            'WellMate notification dose action failed safely: ${error.code}',
          );
          setUnread(true);
        } catch (_) {
          debugPrint('WellMate notification dose action failed safely.');
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
          await _notifications.cancel(
            notificationIdFor(
              target.key,
              sourceRevision: target.version,
            ),
          );
          WellMateRefreshSignal.notifyChanged();
          setUnread(true);
        } on LifeMateApiException catch (error) {
          debugPrint(
            'WellMate notification care-event action failed safely: ${error.code}',
          );
          setUnread(true);
        } catch (_) {
          debugPrint('WellMate notification care-event action failed safely.');
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

  Future<void> reportGroupedDose(
    GroupedMedicationDoseTarget dose, {
    required String status,
  }) async {
    if (status != 'taken' && status != 'skipped') {
      throw ArgumentError.value(status, 'status');
    }
    final apiClient = _apiClient;
    if (apiClient == null) {
      throw const LifeMateApiException(
        statusCode: 401,
        code: 'session_missing',
        message: 'Authentication session is missing.',
      );
    }
    await apiClient.reportDose(
      occurrenceId: dose.occurrenceId,
      clientRequestId: dose.clientRequestId,
      version: dose.version,
      status: status,
      occurredAtUtc: DateTime.now().toUtc(),
    );
    WellMateRefreshSignal.notifyChanged();
  }

  Future<void> snoozeGroupedDose(
    GroupedMedicationDoseTarget dose, {
    required bool isPersian,
  }) => _scheduleSnooze(
    WellMateNotificationTarget(
      type: 'medicine',
      id: dose.occurrenceId,
      version: dose.version,
      clientRequestId: dose.clientRequestId,
      isPersian: isPersian,
    ),
  );

  Future<void> syncReminders(
    List<ScheduleItemModel> items, {
    required String timeZone,
    required bool isPersian,
  }) async {
    await initialize();
    _latestTimeZone = timeZone.trim().isEmpty ? 'UTC' : timeZone.trim();
    tz_data.initializeTimeZones();
    final location = _locationFor(_latestTimeZone);

    if (!_permissionRequested) {
      final android = _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await android?.requestNotificationsPermission();
      _exactAlarmGranted = await android?.requestExactAlarmsPermission();
      _permissionRequested = true;
    }

    final activeScheduledItems = <String, ScheduleItemModel>{
      for (final item in items)
        if (item.status == 'scheduled') _policyKeyForItem(item): item,
    };
    final preservedSnoozeIds = <int>{};
    final preservedSnoozeKeys = <String>{};
    final pending = await _notifications.pendingNotificationRequests();
    for (final request in pending) {
      final payload = request.payload;
      if (payload?.startsWith(_snoozePrefix) != true) continue;
      final target = decodeActionPayload(payload);
      if (target != null && activeScheduledItems.containsKey(target.key)) {
        preservedSnoozeIds.add(request.id);
        preservedSnoozeKeys.add(target.key);
      }
    }

    final nowUtc = DateTime.now().toUtc();
    final medicationCandidates = <GroupedMedicationCandidate>[];
    for (final item in items) {
      if (item.type != 'medicine' || item.status != 'scheduled') continue;
      final itemKey = _policyKeyForItem(item);
      if (preservedSnoozeKeys.contains(itemKey)) continue;
      final scheduledUtc = _scheduledUtc(item, location);
      if (scheduledUtc == null) continue;
      final decision = LifeMateNotificationIntelligence.evaluate(
        personId: 'self',
        sourceId: '${item.type}:${item.id}',
        status: item.status,
        scheduledAtUtc: scheduledUtc,
        nowUtc: nowUtc,
        stage: LifeMateNotificationStage.reminder,
      );
      if (!decision.shouldNotify) continue;
      final triggerUtc = scheduledUtc.subtract(
        Duration(minutes: item.patientReminderMinutesBefore),
      );
      if (!triggerUtc.isAfter(nowUtc)) continue;
      medicationCandidates.add(
        GroupedMedicationCandidate(
          item: item,
          scheduledUtc: scheduledUtc,
          triggerUtc: triggerUtc,
        ),
      );
    }

    final reminders = <LifeMateLocalReminder>[];
    final groups = groupMedicationCandidates(medicationCandidates);
    final groupedOccurrenceIds = <String>{};
    for (final entry in groups.entries) {
      final candidates = entry.value;
      groupedOccurrenceIds.addAll(candidates.map((value) => value.item.id));
      final identities = candidates
          .map((value) => '${value.item.id}@${value.item.version}')
          .toList()
        ..sort();
      final groupKey =
          'wellmate:medication-group:${entry.key.millisecondsSinceEpoch}:${identities.join(',')}';
      final groupRevision = LifeMateReminderIdentity.stableRevisionFor(
        identities.join('|'),
      );
      final target = GroupedMedicationNotificationTarget(
        groupKey: groupKey,
        isPersian: isPersian,
        doses: [
          for (final candidate in candidates)
            GroupedMedicationDoseTarget(
              occurrenceId: candidate.item.id,
              version: candidate.item.version,
              clientRequestId: LifeMateApiClient.createClientRequestId(),
              title: candidate.item.title,
            ),
        ],
      );
      reminders.add(
        LifeMateLocalReminder(
          sourceOccurrenceKey: groupKey,
          sourceRevision: groupRevision,
          triggerUtc: entry.key,
          title: _safeTitle(isPersian),
          body: _safeBody(isPersian),
          notificationDetails: NotificationDetails(
            android: _groupAndroidDetails(isPersian),
          ),
          payload: encodeGroupedMedicationPayload(target),
          accuracy: LifeMateReminderAccuracy.exact,
        ),
      );
    }

    for (final item in items) {
      if (item.type == 'medicine' && groupedOccurrenceIds.contains(item.id)) {
        continue;
      }
      final itemKey = _policyKeyForItem(item);
      if (preservedSnoozeKeys.contains(itemKey)) continue;
      final scheduledUtc = _scheduledUtc(item, location);
      if (scheduledUtc == null) continue;
      final decision = LifeMateNotificationIntelligence.evaluate(
        personId: 'self',
        sourceId: '${item.type}:${item.id}',
        status: item.status,
        scheduledAtUtc: scheduledUtc,
        nowUtc: nowUtc,
        stage: LifeMateNotificationStage.reminder,
      );
      if (!decision.shouldNotify) continue;
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
      reminders.add(
        LifeMateLocalReminder(
          sourceOccurrenceKey: decision.deduplicationKey,
          sourceRevision: item.version,
          triggerUtc: triggerUtc,
          title: _safeTitle(isPersian),
          body: _safeBody(isPersian),
          notificationDetails: NotificationDetails(
            android: _androidDetails(target),
          ),
          payload: encodeActionPayload(target),
          accuracy: LifeMateReminderAccuracy.exact,
        ),
      );
    }

    final result = await _reminderScheduler.sync(
      reminders: reminders,
      timeZone: _latestTimeZone,
      exactAlarmGranted: _exactAlarmGranted,
      ownsPendingRequest: _ownsWellMatePendingRequest,
      preservePendingRequest: (request) =>
          preservedSnoozeIds.contains(request.id),
    );
    _updateFallbackState(result.usedInexactFallback);
  }

  Future<void> _scheduleSnooze(WellMateNotificationTarget target) async {
    await initialize();
    final trigger = DateTime.now().toUtc().add(_snoozeDuration);
    final result = await _reminderScheduler.sync(
      reminders: <LifeMateLocalReminder>[
        LifeMateLocalReminder(
          sourceOccurrenceKey: target.key,
          sourceRevision: target.version,
          triggerUtc: trigger,
          title: _safeTitle(target.isPersian),
          body: target.isPersian
              ? 'برای مرور یادآور، LifeMate را باز کنید.'
              : 'Open LifeMate to review your reminder.',
          notificationDetails: NotificationDetails(
            android: _androidDetails(target),
          ),
          payload: encodeActionPayload(target, snoozed: true),
          accuracy: LifeMateReminderAccuracy.exact,
        ),
      ],
      timeZone: _latestTimeZone,
      exactAlarmGranted: _exactAlarmGranted,
    );
    _updateFallbackState(result.usedInexactFallback);
  }

  static bool _ownsWellMatePendingRequest(PendingNotificationRequest request) {
    final payload = request.payload;
    return payload?.startsWith(_reminderPrefix) == true ||
        payload?.startsWith(_snoozePrefix) == true ||
        payload?.startsWith(wellMateGroupedMedicationPrefix) == true ||
        payload?.startsWith('dose:') == true;
  }

  void _updateFallbackState(bool value) {
    if (_inexactFallbackActive == value) return;
    _inexactFallbackActive = value;
    notifyListeners();
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
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
    category: AndroidNotificationCategory.reminder,
    visibility: NotificationVisibility.private,
    actions: actionButtonsForTarget(target),
  );

  static AndroidNotificationDetails _groupAndroidDetails(bool isPersian) =>
      AndroidNotificationDetails(
        'wellmate_treatment_reminders',
        isPersian
            ? 'یادآور برنامه درمان و مراقبت'
            : 'Treatment and care reminders',
        channelDescription: isPersian
            ? 'یادآورهای دارو، ویزیت و تزریق WellMate'
            : 'WellMate medication, visit and injection reminders',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        category: AndroidNotificationCategory.reminder,
        visibility: NotificationVisibility.private,
        groupKey: 'wellmate_medication_groups',
        actions: <AndroidNotificationAction>[
          AndroidNotificationAction(
            groupOpenActionId,
            isPersian ? 'بررسی' : 'Review',
            showsUserInterface: true,
            cancelNotification: false,
          ),
        ],
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

  DateTime? _scheduledUtc(ScheduleItemModel item, tz.Location location) {
    if (item.scheduledAtUtc != null) return item.scheduledAtUtc!.toUtc();
    final date = item.startDate;
    final parts = item.time.split(':');
    if (date == null || parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1].split(' ').first);
    if (hour == null || minute == null) return null;
    return tz.TZDateTime(
      location,
      date.year,
      date.month,
      date.day,
      hour,
      minute,
    ).toUtc();
  }

  static tz.Location _locationFor(String timeZone) {
    try {
      return tz.getLocation(timeZone);
    } catch (_) {
      return tz.UTC;
    }
  }

  static String _safeTitle(bool persian) =>
      persian ? 'یادآور LifeMate' : 'LifeMate reminder';

  static String _safeBody(bool persian) => persian
      ? 'برای مرور برنامه، LifeMate را باز کنید.'
      : 'Open LifeMate to review your schedule.';

  static String _policyKeyForItem(ScheduleItemModel item) =>
      LifeMateNotificationIntelligence.deduplicationKey(
        personId: 'self',
        sourceId: '${item.type}:${item.id}',
        stage: LifeMateNotificationStage.reminder,
      );

  static int notificationIdFor(
    String value, {
    int sourceRevision = 0,
  }) => LifeMateReminderIdentity.notificationIdFor(
    value,
    sourceRevision: sourceRevision,
  );

  void setUnread(bool value) {
    _hasUnread = value;
    notifyListeners();
  }
}