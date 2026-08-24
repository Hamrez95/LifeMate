import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:url_launcher/url_launcher.dart';

import '../core/utils/string_extensions.dart';
import '../models/care_recipient_alert.dart';
import '../models/care_recipient_reminder.dart';

class CareCompletionCopy {
  const CareCompletionCopy({required this.title, required this.body});

  final String title;
  final String body;
}

class CareNotificationProvider extends ChangeNotifier {
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  final Map<String, String> _lastMissedOccurrenceByPatient = {};
  LifeMateApiClient? _apiClient;
  NotificationResponse? _pendingResponse;
  bool _initialized = false;
  bool _permissionRequested = false;

  void attachApiClient(LifeMateApiClient apiClient) {
    _apiClient = apiClient;
    final pending = _pendingResponse;
    if (pending != null) {
      _pendingResponse = null;
      unawaited(_handleNotificationResponse(pending));
    }
  }

  Future<bool?> notificationPermissionEnabled() async {
    await initialize();
    final android = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return android?.areNotificationsEnabled();
  }

  Future<bool> openPatientDialer(String patientUserId) async {
    final apiClient = _apiClient;
    if (apiClient == null) return false;
    try {
      final relationships = await apiClient.getCareRelationships();
      final phone = resolveAuthorizedPatientPhone(
        relationships,
        patientUserId: patientUserId,
      );
      if (phone == null) return false;
      return await launchUrl(
        Uri(scheme: 'tel', path: phone),
        mode: LaunchMode.externalApplication,
      );
    } catch (error) {
      debugPrint('CareMate call action failed safely: $error');
      return false;
    }
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
    if (_apiClient == null) {
      _pendingResponse = response;
      return;
    }
    unawaited(_handleNotificationResponse(response));
  }

  Future<void> _handleNotificationResponse(NotificationResponse response) async {
    if (response.actionId != 'care-call') return;
    final patientUserId = _patientIdFromPayload(response.payload);
    if (patientUserId == null) return;
    await openPatientDialer(patientUserId);
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
    final relationships = await _safeRelationships();
    final allowedCandidates = candidates.where(
      (reminder) => allowsReminderForRelationships(
        relationships,
        patientUserId: reminder.patientUserId,
        kind: reminder.kind,
      ),
    );
    final reminders = selectEarliestReminderPerPatient(allowedCandidates);
    for (final reminder in reminders) {
      final relationship = _relationshipForPatient(
        relationships,
        reminder.patientUserId,
      );
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
                en: 'Next program of people in care',
              ),
              en: 'Next program of people in care',
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
            visibility: _visibilityForRelationship(relationship),
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

    final relationships = await _safeRelationships();
    await _syncCompletionNotifications(relationships, isPersian: isPersian);
    final allowedCandidates = candidates.where(
      (alert) => allowsMissedForRelationships(
        relationships,
        patientUserId: alert.patientUserId,
      ),
    );
    final nowUtc = DateTime.now().toUtc();
    final alerts = selectLatestMissedAlertPerPatient(
      allowedCandidates,
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
      final relationship = _relationshipForPatient(
        relationships,
        alert.patientUserId,
      );
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
      final phone = resolveAuthorizedPatientPhone(
        relationships,
        patientUserId: alert.patientUserId,
      );
      final actions = phone == null
          ? const <AndroidNotificationAction>[]
          : <AndroidNotificationAction>[
              AndroidNotificationAction(
                'care-call',
                LifeMateRuntimeLocale.select(fa: 'تماس', en: 'Call'),
                showsUserInterface: true,
                cancelNotification: false,
              ),
            ];

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
            visibility: _visibilityForRelationship(relationship),
            onlyAlertOnce: true,
            actions: actions,
          ),
        ),
        payload:
            'care-missed:${alert.patientUserId}:${alert.kind}:${alert.occurrenceId}',
      );
      _lastMissedOccurrenceByPatient[alert.patientUserId] = alert.occurrenceId;
    }
  }

  Future<void> _syncCompletionNotifications(
    Iterable<Map<String, dynamic>> relationships, {
    required bool isPersian,
  }) async {
    final apiClient = _apiClient;
    if (apiClient == null) return;
    for (final relationship in relationships) {
      final relationshipId = relationship['id']?.toString().trim();
      if (relationshipId == null ||
          relationshipId.isEmpty ||
          relationship['status']?.toString().toLowerCase() != 'active' ||
          relationship['notificationPreferences'] is! Map) {
        continue;
      }
      List<Map<String, dynamic>> items;
      try {
        items = await apiClient.claimCareCompletionNotifications(
          relationshipId: relationshipId,
        );
      } catch (error) {
        debugPrint('CareMate completion claim failed safely: $error');
        continue;
      }
      for (final item in items) {
        final sourceEventId = item['sourceEventId']?.toString().trim();
        final sourceKey = item['sourceKey']?.toString().trim();
        final patientUserId = item['patientUserId']?.toString().trim();
        if (sourceEventId == null ||
            sourceEventId.isEmpty ||
            patientUserId == null ||
            patientUserId.isEmpty) {
          continue;
        }
        final stableKey = sourceKey == null || sourceKey.isEmpty
            ? sourceEventId
            : sourceKey;
        final copy = completionCopy(item, isPersian: isPersian);
        await _notifications.show(
          _notificationId('completion:$stableKey'),
          copy.title,
          copy.body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              'caremate_treatment_completion',
              LifeMateRuntimeLocale.select(
                fa: 'خبر خوب مراقبت',
                en: 'Care reassurance',
              ),
              channelDescription: LifeMateRuntimeLocale.select(
                fa: 'ثبت انجام درمان توسط فرد تحت مراقبت، مطابق تنظیمات شما',
                en: 'Recorded treatment completion, according to your preferences',
              ),
              importance: Importance.defaultImportance,
              priority: Priority.defaultPriority,
              category: AndroidNotificationCategory.status,
              visibility: _visibilityForDetail(
                item['lockScreenDetail']?.toString(),
              ),
              onlyAlertOnce: true,
            ),
          ),
          payload: 'care-completion:$patientUserId:$sourceEventId',
        );
      }
    }
  }

  Future<List<Map<String, dynamic>>> _safeRelationships() async {
    final apiClient = _apiClient;
    if (apiClient == null) return const [];
    try {
      return await apiClient.getCareRelationships();
    } catch (_) {
      return const [];
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

  static CareCompletionCopy completionCopy(
    Map<String, dynamic> item, {
    required bool isPersian,
  }) {
    final patient = item['patientDisplayName']?.toString().trim();
    final treatment = item['medicationName']?.toString().trim();
    final safePatient = patient == null || patient.isEmpty
        ? LifeMateRuntimeLocale.select(
            fa: 'فرد تحت مراقبت',
            en: 'Your loved one',
          )
        : patient;
    final safeTreatment = treatment == null || treatment.isEmpty
        ? LifeMateRuntimeLocale.select(fa: 'درمان', en: 'treatment')
        : treatment;
    final evidence = item['evidenceClass']?.toString().toLowerCase();

    return CareCompletionCopy(
      title: LifeMateRuntimeLocale.select(
        fa: '💚 یک خبر خوب از $safePatient',
        en: '💚 A reassuring update from $safePatient',
      ),
      body: evidence == 'self_reported'
          ? LifeMateRuntimeLocale.select(
              fa: '$safePatient ثبت کرد که $safeTreatment را مصرف کرده.',
              en: '$safePatient recorded $safeTreatment as taken.',
            )
          : LifeMateRuntimeLocale.select(
              fa: 'برای $safePatient انجام $safeTreatment ثبت شد.',
              en: 'A completion was recorded for $safePatient: $safeTreatment.',
            ),
    );
  }

  static bool allowsMissedForRelationships(
    Iterable<Map<String, dynamic>> relationships, {
    required String patientUserId,
  }) {
    final relationship = _relationshipForPatient(relationships, patientUserId);
    final preferences = _preferences(relationship);
    return relationship != null &&
        preferences['enabled'] != false &&
        preferences['missedAlertsEnabled'] != false;
  }

  static bool allowsReminderForRelationships(
    Iterable<Map<String, dynamic>> relationships, {
    required String patientUserId,
    required String kind,
  }) {
    final relationship = _relationshipForPatient(relationships, patientUserId);
    final preferences = _preferences(relationship);
    if (relationship == null || preferences['enabled'] == false) return false;
    if (kind == 'appointment' || kind == 'injection') {
      return preferences['careEventsEnabled'] != false;
    }
    return true;
  }

  static String? resolveAuthorizedPatientPhone(
    Iterable<Map<String, dynamic>> relationships, {
    required String patientUserId,
  }) {
    final relationship = _relationshipForPatient(relationships, patientUserId);
    if (relationship == null) return null;
    final value = relationship['patientPhoneNumber']?.toString().trim();
    if (value != null && value.isNotEmpty) return value;
    return null;
  }

  static Map<String, dynamic>? _relationshipForPatient(
    Iterable<Map<String, dynamic>> relationships,
    String patientUserId,
  ) {
    for (final relationship in relationships) {
      if (relationship['patientUserId']?.toString() == patientUserId &&
          relationship['status']?.toString().toLowerCase() == 'active') {
        return relationship;
      }
    }
    return null;
  }

  static Map<String, dynamic> _preferences(Map<String, dynamic>? relationship) {
    final value = relationship?['notificationPreferences'];
    return value is Map<String, dynamic> ? value : const <String, dynamic>{};
  }

  static NotificationVisibility _visibilityForRelationship(
    Map<String, dynamic>? relationship,
  ) => _visibilityForDetail(
    _preferences(relationship)['lockScreenDetail']?.toString(),
  );

  static NotificationVisibility _visibilityForDetail(String? detail) {
    return switch (detail?.toLowerCase()) {
      'full' => NotificationVisibility.public,
      'hidden' => NotificationVisibility.secret,
      _ => NotificationVisibility.private,
    };
  }

  static String? _patientIdFromPayload(String? payload) {
    if (payload == null || !payload.startsWith('care-missed:')) return null;
    final parts = payload.split(':');
    if (parts.length < 4) return null;
    final patientUserId = parts[1].trim();
    return patientUserId.isEmpty ? null : patientUserId;
  }

  static String _kindTitle(String kind) => switch (kind) {
    'appointment' => LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'ویزیت بعدی', en: 'Next visit'),
      en: 'Next visit',
    ),
    'injection' => LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'تزریق بعدی', en: 'Next injection'),
      en: 'Next injection',
    ),
    _ => LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'داروی بعدی', en: 'Next medication'),
      en: 'Next medication',
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
