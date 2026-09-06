import 'cocoon_pregnancy.dart';
import 'shared_offline_runtime_web.dart' show LifeMateSharedOfflineRuntime;

final class CocoonPregnancyOfflineSnapshotCache {
  CocoonPregnancyOfflineSnapshotCache._();

  static Future<CocoonPregnancyOfflineSnapshotCache> open({
    required LifeMateSharedOfflineRuntime runtime,
    Object? store,
    DateTime Function()? now,
  }) => Future<CocoonPregnancyOfflineSnapshotCache>.error(_unsupported());

  Future<void> writeCanonicalOwnerSnapshot(
    CocoonPregnancySnapshot snapshot,
  ) => Future<void>.error(_unsupported());

  Future<CocoonPregnancySnapshot?> readCanonicalOwnerSnapshot() =>
      Future<CocoonPregnancySnapshot?>.error(_unsupported());

  void close() {}

  static UnsupportedError _unsupported() => UnsupportedError(
    'Protected offline health execution is unavailable on web.',
  );
}

final class CocoonPregnancyOfflineSnapshotScopeException implements Exception {
  const CocoonPregnancyOfflineSnapshotScopeException();

  @override
  String toString() =>
      'Cocoon pregnancy snapshot does not belong to the adopted Person namespace.';
}
