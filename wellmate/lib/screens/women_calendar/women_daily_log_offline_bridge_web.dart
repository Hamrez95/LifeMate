import 'package:lifemate_client/lifemate_client.dart';
import 'package:lifemate_core/lifemate_core.dart';

import 'women_offline_owner_dashboard.dart';

final class WomenDailyLogOfflineBridge {
  const WomenDailyLogOfflineBridge._();

  static Future<WomenDailyLogOfflineBridge> open({
    required LifeMateApiClient apiClient,
  }) => Future<WomenDailyLogOfflineBridge>.error(
    UnsupportedError(
      'Protected offline health execution is unavailable on web.',
    ),
  );

  Future<LifeMateWomenDailyLogProjectionResult> project({
    required Iterable<Map<String, dynamic>> serverRows,
    required DateTime fromDate,
    required DateTime toDate,
  }) => Future<LifeMateWomenDailyLogProjectionResult>.error(
    UnsupportedError(
      'Protected offline health execution is unavailable on web.',
    ),
  );

  Future<void> cacheServerDay({
    required DateTime date,
    required Iterable<Map<String, dynamic>> serverRows,
  }) => Future<void>.error(
    UnsupportedError(
      'Protected offline health execution is unavailable on web.',
    ),
  );

  Future<void> cacheServerRange({
    required DateTime fromDate,
    required DateTime toDate,
    required Iterable<Map<String, dynamic>> serverRows,
  }) => Future<void>.error(
    UnsupportedError(
      'Protected offline health execution is unavailable on web.',
    ),
  );

  Future<void> cacheOwnerDashboard({
    required Map<String, dynamic> profile,
    required Iterable<Map<String, dynamic>> episodes,
    required Iterable<Map<String, dynamic>> dailyLogs,
    required DateTime fromDate,
    required DateTime toDate,
  }) => Future<void>.error(
    UnsupportedError(
      'Protected offline health execution is unavailable on web.',
    ),
  );

  Future<List<Map<String, dynamic>>?> readCachedServerDay(DateTime date) =>
      Future<List<Map<String, dynamic>>?>.error(
        UnsupportedError(
          'Protected offline health execution is unavailable on web.',
        ),
      );

  Future<List<Map<String, dynamic>>?> readCachedServerRange({
    required DateTime fromDate,
    required DateTime toDate,
  }) => Future<List<Map<String, dynamic>>?>.error(
    UnsupportedError(
      'Protected offline health execution is unavailable on web.',
    ),
  );

  Future<WomenOfflineOwnerDashboard?> readOwnerDashboard({
    required DateTime fromDate,
    required DateTime toDate,
  }) => Future<WomenOfflineOwnerDashboard?>.error(
    UnsupportedError(
      'Protected offline health execution is unavailable on web.',
    ),
  );

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
  }) => Future<void>.error(
    UnsupportedError(
      'Protected offline health execution is unavailable on web.',
    ),
  );

  Future<void> enqueueEpisodeCreate({
    required String mutationId,
    required DateTime startedOn,
    DateTime? endedOn,
    String? privateNotes,
    DateTime? createdAtUtc,
  }) => Future<void>.error(
    UnsupportedError(
      'Protected offline health execution is unavailable on web.',
    ),
  );

  Future<void> coalescePendingEpisodeCreate({
    required String mutationId,
    required DateTime startedOn,
    DateTime? endedOn,
    String? privateNotes,
  }) => Future<void>.error(
    UnsupportedError(
      'Protected offline health execution is unavailable on web.',
    ),
  );

  Future<List<Map<String, dynamic>>> pendingEpisodeCreates() =>
      Future<List<Map<String, dynamic>>>.error(
        UnsupportedError(
          'Protected offline health execution is unavailable on web.',
        ),
      );

  Future<void> enqueueEpisodeUpdate({
    required String mutationId,
    required String episodeId,
    required int version,
    required DateTime startedOn,
    DateTime? endedOn,
    String? privateNotes,
    DateTime? createdAtUtc,
  }) => Future<void>.error(
    UnsupportedError(
      'Protected offline health execution is unavailable on web.',
    ),
  );

  Future<LifeMateOfflineSyncResult> flush() =>
      Future<LifeMateOfflineSyncResult>.error(
        UnsupportedError(
          'Protected offline health execution is unavailable on web.',
        ),
      );

  void close() {}
}
