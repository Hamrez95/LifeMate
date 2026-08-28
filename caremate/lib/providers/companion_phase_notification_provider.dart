import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:lifemate_client/lifemate_client.dart';

/// Privacy-first companion phase notification synchronizer.
///
/// It intentionally does not queue sensitive phase predictions days in advance.
/// Each local notification is generated only after a fresh server read and a
/// server-authorized impression write. This means cycle edits and revocations
/// are reconciled before future notification generation instead of relying on
/// stale device-side health data.
class CompanionPhaseNotificationProvider extends ChangeNotifier {
  CompanionPhaseNotificationProvider({
    FlutterLocalNotificationsPlugin? notifications,
    LifeMateCompanionCareApi? companionApi,
  })  : _notifications = notifications ?? FlutterLocalNotificationsPlugin(),
        _companionApi = companionApi ?? LifeMateCompanionCareApi.fromEnvironment();

  final FlutterLocalNotificationsPlugin _notifications;
  final LifeMateCompanionCareApi _companionApi;
  final LifeMateCompanionPhaseNotificationEngine _engine =
      const LifeMateCompanionPhaseNotificationEngine();

  LifeMateApiClient? _apiClient;
  Timer? _timer;
  bool _initialized = false;
  bool _syncing = false;

  Future<void> initialize() async {
    if (_initialized) return;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _notifications.initialize(settings);
    _initialized = true;
  }

  void attachApiClient(LifeMateApiClient apiClient) {
    _apiClient = apiClient;
    _timer?.cancel();
    unawaited(syncNow());
    _timer = Timer.periodic(
      const Duration(hours: 1),
      (_) => unawaited(syncNow()),
    );
  }

  Future<void> syncNow() async {
    if (_syncing) return;
    final api = _apiClient;
    if (api == null) return;
    _syncing = true;
    try {
      await initialize();
      final android = _notifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (await android?.areNotificationsEnabled() != true) return;

      final relationships = await api.getCareRelationships();
      for (final relationship in relationships) {
        await _syncRelationship(api, relationship);
      }
    } catch (error) {
      debugPrint('CareMate companion phase notification sync failed safely: $error');
    } finally {
      _syncing = false;
    }
  }

  Future<void> _syncRelationship(
    LifeMateApiClient api,
    Map<String, dynamic> relationship,
  ) async {
    if (relationship['status']?.toString().toLowerCase() != 'active') return;
    final patientUserId = relationship['patientUserId']?.toString().trim();
    if (patientUserId == null || patientUserId.isEmpty) return;

    final preferences = _map(relationship['notificationPreferences']);
    if (preferences['enabled'] == false) return;

    Map<String, dynamic> summary;
    try {
      summary = await api.getCareRecipientWomenCalendar(
        patientUserId: patientUserId,
      );
    } on LifeMateApiException catch (error) {
      if (_isAccessStopped(error.code)) return;
      rethrow;
    }

    final scopes = _map(summary['privacyScopes']);
    final estimate = _map(summary['estimate']);
    final history = _history(summary['guidanceHistory']);
    final candidate = _engine.select(
      receivePhaseNotifications: scopes['receivePhaseNotifications'] == true,
      viewPhaseSummary: scopes['viewPhaseSummary'] == true,
      viewPeriodTiming: scopes['viewPeriodTiming'] == true,
      caregiverNotificationsEnabled: preferences['enabled'] != false,
      cycleStart: estimate['cycleStart']?.toString(),
      cycleDay: _int(estimate['cycleDay']),
      detailedPhase: estimate['detailedPhase']?.toString(),
      daysUntilNextPeriod: _int(estimate['daysUntilNextPeriod']),
      nextPeriodStart: estimate['nextPeriodStart']?.toString(),
      confidence: estimate['confidence']?.toString(),
      cyclePattern: estimate['cyclePattern']?.toString(),
      history: history,
      locale: LifeMateRuntimeLocale.languageCode,
      nowUtc: DateTime.now().toUtc(),
    );
    if (candidate == null) return;

    // Re-authorize immediately before any health-sensitive OS surface is shown.
    // The server record endpoint re-checks the active relationship + exact
    // companion scope and also becomes the durable cooldown/dedup receipt.
    try {
      await _companionApi.recordImpression(
        patientUserId: patientUserId,
        guidanceId: candidate.guidanceId,
        contentVersion: candidate.contentVersion,
        category: 'phase',
      );
    } on LifeMateApiException catch (error) {
      if (_isAccessStopped(error.code)) return;
      debugPrint('CareMate phase notification receipt failed safely: ${error.code}');
      return;
    }

    final lockScreen = preferences['lockScreenDetail']?.toString().toLowerCase() ??
        'limited';
    final full = lockScreen == 'full';
    await _notifications.show(
      _notificationId(candidate.guidanceId),
      full ? candidate.title : 'CareMate',
      full ? candidate.fullBody : candidate.privateBody,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'caremate_companion_phase',
          LifeMateRuntimeLocale.select(
            fa: 'همراهی چرخه',
            en: 'Cycle support',
          ),
          channelDescription: LifeMateRuntimeLocale.select(
            fa: 'یادآوری‌های محدود و رضایت‌محور برای همراهی؛ بدون تشخیص پزشکی',
            en: 'Limited consent-scoped supportive reminders without medical diagnosis',
          ),
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          category: AndroidNotificationCategory.status,
          visibility: switch (lockScreen) {
            'full' => NotificationVisibility.public,
            'hidden' => NotificationVisibility.secret,
            _ => NotificationVisibility.private,
          },
          onlyAlertOnce: true,
        ),
      ),
      payload: 'care-companion-phase:$patientUserId:${candidate.guidanceId}',
    );
  }

  static List<LifeMateCompanionPhaseNotificationHistoryItem> _history(
    dynamic raw,
  ) => (raw is List ? raw : const <dynamic>[])
      .whereType<Map>()
      .map((item) {
        final value = Map<String, dynamic>.from(item);
        return LifeMateCompanionPhaseNotificationHistoryItem(
          guidanceId: value['guidanceId']?.toString() ?? '',
          shownAtUtc: DateTime.tryParse(value['shownAtUtc']?.toString() ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        );
      })
      .toList(growable: false);

  static bool _isAccessStopped(String code) =>
      code == 'women_calendar_access_denied' ||
      code == 'women_calendar_not_active' ||
      code == 'person_access_denied';

  static Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : const {};

  static int? _int(dynamic value) =>
      value is int ? value : int.tryParse(value?.toString() ?? '');

  static int _notificationId(String key) {
    var hash = 0x811c9dc5;
    for (final unit in key.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _companionApi.close();
    super.dispose();
  }
}
