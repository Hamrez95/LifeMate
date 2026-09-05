import 'package:http/http.dart' as http;
import 'package:lifemate_core/lifemate_core.dart';

import 'lifemate_api_client.dart' show AccessTokenProvider;
import 'offline_mutation_queue.dart' show LifeMateMutationStorage;
import 'offline_sync_result.dart';
import 'shared_offline_runtime.dart';

/// Native adapter that keeps SQLite-backed types behind a conditional import.
final class LifeMateSharedRuntimeBinding {
  LifeMateSharedRuntimeBinding._(this._runtime);

  final LifeMateSharedOfflineRuntime _runtime;

  String get environmentId => _runtime.namespace.environmentId;
  String get accountId => _runtime.namespace.accountId;
  String get personId => _runtime.namespace.personId;

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
  }) async {
    final runtime = await LifeMateSharedOfflineRuntime.open(
      namespace: LifeMateLocalNamespace(
        environmentId: environmentId,
        accountId: accountId,
        personId: personId,
      ),
      timeZone: timeZone,
      apiBaseUri: apiBaseUri,
      accessToken: accessToken,
      legacyAccountIds: legacyAccountIds,
      legacyStorage: legacyStorage,
      httpClient: httpClient,
      maximumMutationsPerRun: maximumMutationsPerRun,
      now: now,
    );
    return LifeMateSharedRuntimeBinding._(runtime);
  }

  Future<LifeMateOfflineSyncResult> flushDetailed() => _runtime.flushDetailed();

  Future<int> pendingMutationCount() => _runtime.pendingMutationCount();

  Future<Map<String, String>> pendingAdherenceStates() =>
      _runtime.pendingAdherenceStates();

  void close() => _runtime.close();
}
