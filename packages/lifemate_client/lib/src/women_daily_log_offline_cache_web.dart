import 'package:lifemate_core/lifemate_core.dart';

/// Browser stub: health cache persistence deliberately remains native-only.
final class WomenDailyLogOfflineCache {
  const WomenDailyLogOfflineCache._();

  static Future<WomenDailyLogOfflineCache> openDefault({
    required LifeMateLocalNamespace namespace,
  }) => Future<WomenDailyLogOfflineCache>.error(_unsupported());

  Future<void> cacheServerDay({
    required DateTime date,
    required Iterable<Map<String, dynamic>> serverRows,
  }) => Future<void>.error(_unsupported());

  Future<void> cacheServerRange({
    required DateTime fromDate,
    required DateTime toDate,
    required Iterable<Map<String, dynamic>> serverRows,
  }) => Future<void>.error(_unsupported());

  Future<List<Map<String, dynamic>>?> readServerDay(DateTime date) =>
      Future<List<Map<String, dynamic>>?>.error(_unsupported());

  Future<List<Map<String, dynamic>>?> readServerRange({
    required DateTime fromDate,
    required DateTime toDate,
  }) => Future<List<Map<String, dynamic>>?>.error(_unsupported());

  void close() {}

  static UnsupportedError _unsupported() => UnsupportedError(
    'Protected Women Health daily-log cache is unavailable on web.',
  );
}
