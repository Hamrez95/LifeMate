import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:lifemate_client/lifemate_client.dart';

class CompanionPhaseNotificationPresentation {
  const CompanionPhaseNotificationPresentation({
    required this.title,
    required this.body,
    required this.visibility,
  });

  final String title;
  final String body;
  final NotificationVisibility visibility;
}

CompanionPhaseNotificationPresentation companionPhaseNotificationPresentation(
  LifeMateCompanionPhaseNotification candidate,
  String? lockScreenDetail,
) => _presentation(
  title: candidate.title,
  fullBody: candidate.fullBody,
  privateBody: candidate.privateBody,
  lockScreenDetail: lockScreenDetail,
);

CompanionPhaseNotificationPresentation companionMoodNotificationPresentation(
  LifeMateCompanionMoodNotification candidate,
  String? lockScreenDetail,
) => _presentation(
  title: candidate.title,
  fullBody: candidate.fullBody,
  privateBody: candidate.privateBody,
  lockScreenDetail: lockScreenDetail,
);

CompanionPhaseNotificationPresentation _presentation({
  required String title,
  required String fullBody,
  required String privateBody,
  required String? lockScreenDetail,
}) {
  final detail = lockScreenDetail?.trim().toLowerCase() ?? 'limited';
  if (detail == 'full') {
    return CompanionPhaseNotificationPresentation(
      title: title,
      body: fullBody,
      visibility: NotificationVisibility.public,
    );
  }
  return CompanionPhaseNotificationPresentation(
    title: 'CareMate',
    body: privateBody,
    visibility: detail == 'hidden'
        ? NotificationVisibility.secret
        : NotificationVisibility.private,
  );
}

/// Privacy-first companion notification synchronizer.
///
/// The historical class name is retained for compatibility with #106, but the
/// same single hourly pass now evaluates both phase and explicitly shared
/// wellbeing signals. This avoids duplicate timers/network reads and prevents
/// one refresh from fanning out multiple sensitive notifications.
class CompanionPhaseNotificationProvider extends ChangeNotifier {
  CompanionPhaseNotificationProvider({
    FlutterLocalNotificationsPlugin? notifications,
    LifeMateCompanionCareApi? companionApi,
  })  : _notifications = notifications ?? FlutterLocalNotificationsPlugin(),
        _companionApi = companionApi ?? LifeMateCompanionCareApi.fromEnvironment();

  final FlutterLocalNotificationsPlugin _notifications;
  final LifeMateCompanionCareApi _companionApi;
  final LifeMateCompanionPhaseNotificationEngine _phaseEngine =
      const LifeMateCompanionPhaseNotificationEngine();
  final LifeMateCompanionMoodNotificationEngine _moodEngine =
      const LifeMateCompanionMoodNotificationEngine();

  LifeMateApiClient? _apiClient;
  Timer? _timer;
  bool _syncing = false;

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
      // CareNotificationProvider remains the only plugin initializer so its
      // existing response callback (including call actions) is never replaced.
      final android = _notifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (await android?.areNotificationsEnabled() != true) return;

      final relationships = await api.getCareRelationships();
      for (final relationship in relationships) {
        await _syncRelationship(api, relationship);
      }
    } catch (error) {
      debugPrint('CareMate companion notification sync failed safely: $error');
    } finally {
      _syncing = false;
    }
  }

  Future<void> _syncRelationship(
    LifeMateApiClient api,
    Map<String, dynamic> relationship,
  ) async {
    if (relationship['status']?.toString().toLowerCase() != 'active') return;
    if (relationship['notificationPreferences'] is! Map) return;
    final patientUserId = relationship['patientUserId']?.toString().trim();
    if (patientUserId == null || patientUserId.isEmpty) return;

    final preferences = _map(relationship['notificationPreferences']);
    if (preferences['enabled'] != true) return;

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
    final rawHistory = summary['guidanceHistory'];
    final lockScreenDetail = preferences['lockScreenDetail']?.toString();

    // Fresh explicitly-shared wellbeing is more time-sensitive than an
    // estimated phase reminder, so it gets first chance. Returning after a
    // successful mood/energy notification ensures one refresh cannot emit both.
    final shared = _map(summary['latestSharedDailyLog']);
    final moodCandidate = _moodEngine.select(
      receiveMoodSupportNotifications:
          scopes['receiveMoodSupportNotifications'] == true,
      viewSharedWellbeing: scopes['viewSharedWellbeing'] == true,
      caregiverNotificationsEnabled: preferences['enabled'] == true,
      loggedOn: shared['loggedOn']?.toString(),
      mood: shared['mood']?.toString(),
      energyLevel: _int(shared['energyLevel']),
      updatedAtUtc: DateTime.tryParse(shared['updatedAtUtc']?.toString() ?? ''),
      history: _moodHistory(rawHistory),
      locale: LifeMateRuntimeLocale.languageCode,
      nowUtc: DateTime.now().toUtc(),
    );
    if (moodCandidate != null) {
      final recorded = await _recordAuthorized(
        patientUserId: patientUserId,
        guidanceId: moodCandidate.guidanceId,
        contentVersion: moodCandidate.contentVersion,
        category: 'mood',
      );
      if (!recorded) return;
      final presentation = companionMoodNotificationPresentation(
        moodCandidate,
        lockScreenDetail,
      );
      await _notifications.show(
        _notificationId(moodCandidate.guidanceId),
        presentation.title,
        presentation.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'caremate_companion_wellbeing',
            LifeMateRuntimeLocale.select(
              fa: 'همراهی و احوال‌پرسی',
              en: 'Supportive check-ins',
            ),
            channelDescription: LifeMateRuntimeLocale.select(
              fa: 'اعلان‌های محدود بر اساس حال یا انرژی‌ای که صریحاً به اشتراک گذاشته شده است',
              en: 'Limited notifications based only on explicitly shared mood or energy',
            ),
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            category: AndroidNotificationCategory.social,
            visibility: presentation.visibility,
            onlyAlertOnce: true,
          ),
        ),
        payload:
            'care-companion-wellbeing:$patientUserId:${moodCandidate.guidanceId}',
      );
      return;
    }

    final estimate = _map(summary['estimate']);
    final phaseCandidate = _phaseEngine.select(
      receivePhaseNotifications: scopes['receivePhaseNotifications'] == true,
      viewPhaseSummary: scopes['viewPhaseSummary'] == true,
      viewPeriodTiming: scopes['viewPeriodTiming'] == true,
      caregiverNotificationsEnabled: preferences['enabled'] == true,
      cycleStart: estimate['cycleStart']?.toString(),
      cycleDay: _int(estimate['cycleDay']),
      detailedPhase: estimate['detailedPhase']?.toString(),
      daysUntilNextPeriod: _int(estimate['daysUntilNextPeriod']),
      nextPeriodStart: estimate['nextPeriodStart']?.toString(),
      confidence: estimate['confidence']?.toString(),
      cyclePattern: estimate['cyclePattern']?.toString(),
      history: _phaseHistory(rawHistory),
      locale: LifeMateRuntimeLocale.languageCode,
      nowUtc: DateTime.now().toUtc(),
    );
    if (phaseCandidate == null) return;

    final recorded = await _recordAuthorized(
      patientUserId: patientUserId,
      guidanceId: phaseCandidate.guidanceId,
      contentVersion: phaseCandidate.contentVersion,
      category: 'phase',
    );
    if (!recorded) return;

    final presentation = companionPhaseNotificationPresentation(
      phaseCandidate,
      lockScreenDetail,
    );
    await _notifications.show(
      _notificationId(phaseCandidate.guidanceId),
      presentation.title,
      presentation.body,
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
          visibility: presentation.visibility,
          onlyAlertOnce: true,
        ),
      ),
      payload:
          'care-companion-phase:$patientUserId:${phaseCandidate.guidanceId}',
    );
  }

  Future<bool> _recordAuthorized({
    required String patientUserId,
    required String guidanceId,
    required String contentVersion,
    required String category,
  }) async {
    try {
      await _companionApi.recordImpression(
        patientUserId: patientUserId,
        guidanceId: guidanceId,
        contentVersion: contentVersion,
        category: category,
      );
      return true;
    } on LifeMateApiException catch (error) {
      if (!_isAccessStopped(error.code)) {
        debugPrint('CareMate companion notification receipt failed safely: ${error.code}');
      }
      return false;
    }
  }

  static List<LifeMateCompanionPhaseNotificationHistoryItem> _phaseHistory(
    dynamic raw,
  ) => (raw is List ? raw : const <dynamic>[])
      .whereType<Map>()
      .map((item) {
        final value = Map<String, dynamic>.from(item);
        return LifeMateCompanionPhaseNotificationHistoryItem(
          guidanceId: value['guidanceId']?.toString() ?? '',
          shownAtUtc: _historyDate(value),
        );
      })
      .toList(growable: false);

  static List<LifeMateCompanionMoodNotificationHistoryItem> _moodHistory(
    dynamic raw,
  ) => (raw is List ? raw : const <dynamic>[])
      .whereType<Map>()
      .map((item) {
        final value = Map<String, dynamic>.from(item);
        return LifeMateCompanionMoodNotificationHistoryItem(
          guidanceId: value['guidanceId']?.toString() ?? '',
          shownAtUtc: _historyDate(value),
        );
      })
      .toList(growable: false);

  static DateTime _historyDate(Map<String, dynamic> value) =>
      DateTime.tryParse(value['shownAtUtc']?.toString() ?? '') ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

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
