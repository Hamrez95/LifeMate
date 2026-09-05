import 'package:http/http.dart' as http;
import 'package:lifemate_core/lifemate_core.dart';

import 'lifemate_api_client.dart' show AccessTokenProvider;
import 'offline_mutation_queue.dart' show LifeMateMutationStorage;
import 'offline_sync_result.dart';

final class LifeMateOfflineNamespace {
  LifeMateOfflineNamespace({
    required String environmentId,
    required String accountId,
    required String personId,
  }) : environmentId = _required(environmentId, 'environmentId'),
       accountId = _required(accountId, 'accountId'),
       personId = _required(personId, 'personId');

  final String environmentId;
  final String accountId;
  final String personId;

  static String _required(String value, String field) {
    final normalized = value.trim();
    if (normalized.isEmpty) throw ArgumentError.value(value, field);
    return normalized;
  }
}

/// Web builds intentionally do not instantiate the native encrypted SQLite
/// execution engine. Remote API behavior remains available, while offline
/// health replay/projection persistence fails closed instead of falling back to
/// an unprotected browser store.
final class LifeMateSharedOfflineRuntime {
  LifeMateSharedOfflineRuntime._(this.namespace);

  final LifeMateOfflineNamespace namespace;

  static Future<LifeMateSharedOfflineRuntime> open({
    required Object namespace,
    required String timeZone,
    required Uri apiBaseUri,
    required AccessTokenProvider accessToken,
    Set<String> legacyAccountIds = const <String>{},
    Object? store,
    LifeMateMutationStorage? legacyStorage,
    http.Client? httpClient,
    int maximumMutationsPerRun = 25,
    DateTime Function()? now,
  }) async {
    throw UnsupportedError(
      'Protected offline health execution is unavailable on web.',
    );
  }

  Future<int> importLegacyPending() => Future<int>.value(0);

  Future<LifeMateOfflineSyncResult> flushDetailed() =>
      Future<LifeMateOfflineSyncResult>.value(const LifeMateOfflineSyncResult());

  Future<LifeMateLocalSyncCheckpoint?> careEventCheckpoint() =>
      Future<LifeMateLocalSyncCheckpoint?>.error(
        UnsupportedError(
          'Protected offline health execution is unavailable on web.',
        ),
      );

  Future<LifeMateProjectionReconcileResult> applyCareEventPage({
    required LifeMateProjectionPullPage page,
    LifeMateBeforeProjectionCheckpoint? beforeCheckpoint,
  }) => Future<LifeMateProjectionReconcileResult>.error(
    UnsupportedError(
      'Protected offline health execution is unavailable on web.',
    ),
  );

  Future<int> pendingMutationCount() => Future<int>.value(0);

  Future<Map<String, String>> pendingAdherenceStates() =>
      Future<Map<String, String>>.value(const <String, String>{});

  void close() {}
}
