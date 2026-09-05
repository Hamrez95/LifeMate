import 'package:lifemate_client/lifemate_client.dart';

import 'women_daily_log_offline_bridge.dart';

typedef WomenCompanionDashboardFetch = Future<Map<String, dynamic>> Function({
  required DateTime fromDate,
  required DateTime toDate,
});

typedef WomenCompanionOfflinePortOpen =
    Future<WomenCompanionOfflineDashboardPort?> Function();

abstract interface class WomenCompanionOfflineDashboardPort {
  Future<void> cacheOwnerDashboard({
    required Map<String, dynamic> profile,
    required Iterable<Map<String, dynamic>> episodes,
    required Iterable<Map<String, dynamic>> dailyLogs,
    required DateTime fromDate,
    required DateTime toDate,
  });

  Future<Map<String, dynamic>?> readOwnerDashboard({
    required DateTime fromDate,
    required DateTime toDate,
  });

  void close();
}

final class WomenCompanionDashboardLoadResult {
  const WomenCompanionDashboardLoadResult({
    required this.dashboard,
    required this.offlineCached,
  });

  final Map<String, dynamic> dashboard;
  final bool offlineCached;
}

final class WomenCompanionDashboardLoader {
  WomenCompanionDashboardLoader({
    required WomenCompanionDashboardFetch fetchDashboard,
    required WomenCompanionOfflinePortOpen openOffline,
  }) : _fetchDashboard = fetchDashboard,
       _openOffline = openOffline;

  factory WomenCompanionDashboardLoader.forApi(LifeMateApiClient apiClient) {
    return WomenCompanionDashboardLoader(
      fetchDashboard: ({required fromDate, required toDate}) => apiClient
          .getWomenCalendarDashboard(fromDate: fromDate, toDate: toDate),
      openOffline: () async {
        try {
          final bridge = await WomenDailyLogOfflineBridge.open(
            apiClient: apiClient,
          );
          return _WomenCompanionOfflineDashboardBridgePort(bridge);
        } on UnsupportedError {
          return null;
        } on LifeMateApiException {
          return null;
        } on StateError {
          return null;
        }
      },
    );
  }

  final WomenCompanionDashboardFetch _fetchDashboard;
  final WomenCompanionOfflinePortOpen _openOffline;

  Future<WomenCompanionDashboardLoadResult> load({
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    WomenCompanionOfflineDashboardPort? offline;
    try {
      offline = await _openOffline();
      try {
        final dashboard = await _fetchDashboard(
          fromDate: fromDate,
          toDate: toDate,
        );
        await _cacheCanonicalOwnerDashboard(
          offline: offline,
          dashboard: dashboard,
          fromDate: fromDate,
          toDate: toDate,
        );
        return WomenCompanionDashboardLoadResult(
          dashboard: dashboard,
          offlineCached: false,
        );
      } on LifeMateApiException catch (error) {
        if (offline == null || !_canUseOwnerCache(error)) rethrow;
        try {
          final cached = await offline.readOwnerDashboard(
            fromDate: fromDate,
            toDate: toDate,
          );
          if (cached == null) rethrow;
          return WomenCompanionDashboardLoadResult(
            dashboard: cached,
            offlineCached: true,
          );
        } catch (_) {
          rethrow;
        }
      }
    } finally {
      offline?.close();
    }
  }

  static Future<void> _cacheCanonicalOwnerDashboard({
    required WomenCompanionOfflineDashboardPort? offline,
    required Map<String, dynamic> dashboard,
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    if (offline == null) return;
    final profile = dashboard['profile'];
    final episodes = dashboard['episodes'];
    final dailyLogs = dashboard['dailyLogs'];
    if (profile is! Map<String, dynamic> ||
        episodes is! List ||
        dailyLogs is! List) {
      return;
    }
    final typedEpisodes = episodes.whereType<Map<String, dynamic>>();
    final typedDailyLogs = dailyLogs.whereType<Map<String, dynamic>>();
    if (typedEpisodes.length != episodes.length ||
        typedDailyLogs.length != dailyLogs.length) {
      return;
    }
    try {
      await offline.cacheOwnerDashboard(
        profile: profile,
        episodes: typedEpisodes,
        dailyLogs: typedDailyLogs,
        fromDate: fromDate,
        toDate: toDate,
      );
    } catch (_) {
      // A protected local-cache failure must not turn a canonical online read
      // into a failed health-data operation. Offline fallback remains absent.
    }
  }

  static bool _canUseOwnerCache(LifeMateApiException error) {
    if (error.statusCode == 401 ||
        error.statusCode == 403 ||
        error.statusCode == 409 ||
        error.code == 'women_calendar_feature_disabled') {
      return false;
    }
    return error.statusCode == 0 ||
        error.statusCode == 408 ||
        error.statusCode == 429 ||
        error.statusCode == 500 ||
        error.statusCode == 502 ||
        error.statusCode == 503 ||
        error.statusCode == 504 ||
        const <String>{
          'network_unavailable',
          'network_timeout',
          'retry_budget_exhausted',
        }.contains(error.code);
  }
}

final class _WomenCompanionOfflineDashboardBridgePort
    implements WomenCompanionOfflineDashboardPort {
  _WomenCompanionOfflineDashboardBridgePort(this._bridge);

  final WomenDailyLogOfflineBridge _bridge;

  @override
  Future<void> cacheOwnerDashboard({
    required Map<String, dynamic> profile,
    required Iterable<Map<String, dynamic>> episodes,
    required Iterable<Map<String, dynamic>> dailyLogs,
    required DateTime fromDate,
    required DateTime toDate,
  }) => _bridge.cacheOwnerDashboard(
    profile: profile,
    episodes: episodes,
    dailyLogs: dailyLogs,
    fromDate: fromDate,
    toDate: toDate,
  );

  @override
  Future<Map<String, dynamic>?> readOwnerDashboard({
    required DateTime fromDate,
    required DateTime toDate,
  }) async => (await _bridge.readOwnerDashboard(
    fromDate: fromDate,
    toDate: toDate,
  ))?.toDashboardMap();

  @override
  void close() => _bridge.close();
}
