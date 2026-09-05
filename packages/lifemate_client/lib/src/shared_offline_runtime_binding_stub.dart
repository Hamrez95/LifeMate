import 'package:http/http.dart' as http;

import 'lifemate_api_client.dart' show AccessTokenProvider;
import 'offline_mutation_queue.dart' show LifeMateMutationStorage;
import 'offline_sync_result.dart';

/// Non-native binding for the protected shared offline runtime.
///
/// Browser storage is not treated as equivalent to the encrypted native SQLite
/// store. Normal web bootstrap never calls this binding and retains the legacy
/// durable replay path. Explicit use fails closed.
final class LifeMateSharedRuntimeBinding {
  LifeMateSharedRuntimeBinding._({
    required this.environmentId,
    required this.accountId,
    required this.personId,
  });

  final String environmentId;
  final String accountId;
  final String personId;

  static Future<LifeMateSharedRuntimeBinding> open({
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
