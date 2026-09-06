import 'package:lifemate_client/lifemate_client.dart';
import 'package:lifemate_core/lifemate_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'women_offline_owner_dashboard.dart';

final class WomenDailyLogOfflineBridge {
  WomenDailyLogOfflineBridge._(this._runtime, this._dailyLogCache);

  final LifeMateSharedOfflineRuntime _runtime;
  final WomenDailyLogOfflineCache _dailyLogCache;

  static Future<WomenDailyLogOfflineBridge> open({
    required LifeMateApiClient apiClient,
  }) async {
    final session = Supabase.instance.client.auth.currentSession;
    final legacyAccountId = session?.user.id.trim();
    if (legacyAccountId == null || legacyAccountId.isEmpty) {
      throw const LifeMateApiException(
        statusCode: 401,
        code: 'offline_identity_unavailable',
        message: 'Authenticated identity is unavailable for offline runtime.',
      );
    }

    final capabilities = await apiClient.getCapabilities();
    final personId = capabilities.selfPersonId?.trim();
    final accountId = capabilities.accountId.trim();
    if (personId == null || personId.isEmpty || accountId.isEmpty) {
      throw const LifeMateApiException(
        statusCode: 409,
        code: 'identity_person_mapping_missing',
        message: 'The LifeMate person mapping is unavailable.',
      );
    }

    final config = AppConfig.fromEnvironment();
    final localNamespace = LifeMateLocalNamespace(
      environmentId: config.apiBaseUri.toString(),
      accountId: accountId,
      personId: personId,
    );
    final runtime = await LifeMateSharedOfflineRuntime.open(
      namespace: LifeMateOfflineNamespace(
        environmentId: localNamespace.environmentId,
        accountId: localNamespace.accountId,
        personId: localNamespace.personId,
      ),
      timeZone: 'Asia/Tehran',
      apiBaseUri: config.apiBaseUri,
      accessToken: () =>
          Supabase.instance.client.auth.currentSession?.accessToken,
      legacyAccountIds: <String>{legacyAccountId},
    );
    try {
      final dailyLogCache = await WomenDailyLogOfflineCache.openDefault(
        namespace: localNamespace,
      );
      return WomenDailyLogOfflineBridge._(runtime, dailyLogCache);
    } catch (_) {
      runtime.close();
      rethrow;
    }
  }

  Future<LifeMateWomenDailyLogProjectionResult> project({
    required Iterable<Map<String, dynamic>> serverRows,
    required DateTime fromDate,
    required DateTime toDate,
  }) => _runtime.projectWomenDailyLogs(
    serverRows: serverRows,
    fromDate: fromDate,
    toDate: toDate,
  );

  Future<void> cacheServerDay({
    required DateTime date,
    required Iterable<Map<String, dynamic>> serverRows,
  }) => _dailyLogCache.cacheServerDay(date: date, serverRows: serverRows);

  Future<void> cacheServerRange({
    required DateTime fromDate,
    required DateTime toDate,
    required Iterable<Map<String, dynamic>> serverRows,
  }) => _dailyLogCache.cacheServerRange(
    fromDate: fromDate,
    toDate: toDate,
    serverRows: serverRows,
  );

  Future<void> cacheOwnerDashboard({
    required Map<String, dynamic> profile,
    required Iterable<Map<String, dynamic>> episodes,
    required Iterable<Map<String, dynamic>> dailyLogs,
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    final lifecycleState = WomenHealthLifecycleState.parse(
      profile['lifecycleState'],
    );
    await _runtime.cacheWomenCalendarSnapshot(
      profile: profile,
      episodes: episodes,
      lifecycleState: lifecycleState,
    );
    await _dailyLogCache.cacheServerRange(
      fromDate: fromDate,
      toDate: toDate,
      serverRows: dailyLogs,
    );
  }

  Future<List<Map<String, dynamic>>?> readCachedServerDay(DateTime date) =>
      _dailyLogCache.readServerDay(date);

  Future<List<Map<String, dynamic>>?> readCachedServerRange({
    required DateTime fromDate,
    required DateTime toDate,
  }) => _dailyLogCache.readServerRange(fromDate: fromDate, toDate: toDate);

  Future<WomenOfflineOwnerDashboard?> readOwnerDashboard({
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    final snapshot = await _runtime.readWomenCalendarSnapshot();
    if (snapshot == null) return null;
    final dailyLogs = await _dailyLogCache.readServerRange(
      fromDate: fromDate,
      toDate: toDate,
    );
    if (dailyLogs == null) return null;
    return WomenOfflineOwnerDashboard(snapshot: snapshot, dailyLogs: dailyLogs);
  }

  Future<void> enqueueUpsert({
    required String mutationId,
    required DateTime loggedOn,
    required int version,
    String? mood,
    int? energyLevel,
    String? periodFlow,
    String? bloodAppearance,
    String? bloodTexture,
    int? painLevel,
    Set<String> symptoms = const <String>{},
    String? privateNotes,
  }) {
    return _runtime.enqueueWomenDailyLogUpsert(
      mutationId: mutationId,
      loggedOn: loggedOn,
      version: version,
      mood: mood,
      energyLevel: energyLevel,
      periodFlow: periodFlow,
      bloodAppearance: bloodAppearance,
      bloodTexture: bloodTexture,
      painLevel: painLevel,
      symptoms: symptoms,
      privateNotes: privateNotes,
    );
  }

  Future<void> enqueueEpisodeCreate({
    required String mutationId,
    required DateTime startedOn,
    DateTime? endedOn,
    String? privateNotes,
    DateTime? createdAtUtc,
  }) => _runtime.enqueueWomenEpisodeCreate(
    mutationId: mutationId,
    startedOn: startedOn,
    endedOn: endedOn,
    privateNotes: privateNotes,
    createdAtUtc: createdAtUtc,
  );

  Future<void> coalescePendingEpisodeCreate({
    required String mutationId,
    required DateTime startedOn,
    DateTime? endedOn,
    String? privateNotes,
  }) => _runtime.coalescePendingWomenEpisodeCreate(
    mutationId: mutationId,
    startedOn: startedOn,
    endedOn: endedOn,
    privateNotes: privateNotes,
  );

  Future<void> enqueueEpisodeUpdate({
    required String mutationId,
    required String episodeId,
    required int version,
    required DateTime startedOn,
    DateTime? endedOn,
    String? privateNotes,
    DateTime? createdAtUtc,
  }) => _runtime.enqueueWomenEpisodeUpdate(
    mutationId: mutationId,
    episodeId: episodeId,
    version: version,
    startedOn: startedOn,
    endedOn: endedOn,
    privateNotes: privateNotes,
    createdAtUtc: createdAtUtc,
  );

  Future<LifeMateOfflineSyncResult> flush() => _runtime.flushDetailed();

  void close() {
    _dailyLogCache.close();
    _runtime.close();
  }
}
