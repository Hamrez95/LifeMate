import 'package:lifemate_client/lifemate_client.dart';
import 'package:lifemate_core/lifemate_core.dart';

final class WomenDailyLogOfflineBridge {
  const WomenDailyLogOfflineBridge._();

  static Future<WomenDailyLogOfflineBridge> open({
    required LifeMateApiClient apiClient,
  }) => Future<WomenDailyLogOfflineBridge>.error(
    UnsupportedError('Protected offline health execution is unavailable on web.'),
  );

  Future<LifeMateWomenDailyLogProjectionResult> project({
    required Iterable<Map<String, dynamic>> serverRows,
    required DateTime fromDate,
    required DateTime toDate,
  }) => Future<LifeMateWomenDailyLogProjectionResult>.error(
    UnsupportedError('Protected offline health execution is unavailable on web.'),
  );

  Future<void> cacheServerDay({
    required DateTime date,
    required Iterable<Map<String, dynamic>> serverRows,
  }) => Future<void>.error(
    UnsupportedError('Protected offline health execution is unavailable on web.'),
  );

  Future<void> cacheServerRange({
    required DateTime fromDate,
    required DateTime toDate,
    required Iterable<Map<String, dynamic>> serverRows,
  }) => Future<void>.error(
    UnsupportedError('Protected offline health execution is unavailable on web.'),
  );

  Future<List<Map<String, dynamic>>?> readCachedServerDay(DateTime date) =>
      Future<List<Map<String, dynamic>>?>.error(
        UnsupportedError('Protected offline health execution is unavailable on web.'),
      );

  Future<List<Map<String, dynamic>>?> readCachedServerRange({
    required DateTime fromDate,
    required DateTime toDate,
  }) => Future<List<Map<String, dynamic>>?>.error(
    UnsupportedError('Protected offline health execution is unavailable on web.'),
  );

  Future<void> enqueueUpsert({
    required String mutationId,
    required DateTime loggedOn,
    required int version,
    String? periodFlow,
    String? bloodAppearance,
    String? bloodTexture,
    int? painLevel,
    Set<String> symptoms = const <String>{},
    String? privateNotes,
  }) => Future<void>.error(
    UnsupportedError('Protected offline health execution is unavailable on web.'),
  );

  Future<LifeMateOfflineSyncResult> flush() =>
      Future<LifeMateOfflineSyncResult>.error(
        UnsupportedError('Protected offline health execution is unavailable on web.'),
      );

  void close() {}
}
