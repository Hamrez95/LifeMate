import 'package:http/http.dart' as http;

import 'lifemate_api_client.dart' show AccessTokenProvider;
import 'offline_mutation_queue.dart' show LifeMateMutationStorage;
import 'offline_sync_result.dart';

/// Web/non-native placeholder for the protected Account + Person offline runtime.
///
/// LifeMate's encrypted SQLite execution store is a native-device facility. Web
/// deliberately keeps the pre-existing durable replay path and must not pretend
/// that browser storage has the same at-rest guarantees. Calling this runtime
/// explicitly therefore fails closed instead of silently downgrading storage.
final class LifeMateSharedOfflineRuntime {
  LifeMateSharedOfflineRuntime._({
    required this.environmentId,
    required this.accountId,
    required this.personId,
  });

  final String environmentId;
  final String accountId;
  final String personId;

  static Future<LifeMateSharedOfflineRuntime> openForIdentity({
    required String environmentId,
    required String accountId,
    required String personId,
    required String timeZone,
    required Uri apiBaseUri,
    required AccessTokenProvider accessToken,
    Set<String> legacyAccountIds = const <String>{},
    LifeMateMutationStorage? legacyStorage,
    http.Client? httpClient,
    int maximumMutationsPerRun = 25,
    DateTime Function()? now,
  }) {
    throw UnsupportedError(
      'The protected LifeMate shared offline runtime is unavailable on web.',
    );
  }

  Future<LifeMateOfflineSyncResult> flushDetailed() =>
      Future<LifeMateOfflineSyncResult>.value(const LifeMateOfflineSyncResult());

  Future<int> pendingMutationCount() => Future<int>.value(0);

  Future<Map<String, String>> pendingAdherenceStates() =>
      Future<Map<String, String>>.value(const <String, String>{});

  void close() {}
}
