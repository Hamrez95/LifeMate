import 'package:http/http.dart' as http;
import 'package:lifemate_core/lifemate_core.dart';

import 'legacy_mutation_importer.dart';
import 'lifemate_api_client.dart' show AccessTokenProvider;
import 'mutation_replay_transport.dart';
import 'offline_mutation_queue.dart' show LifeMateMutationStorage;
import 'offline_sync_result.dart';

/// Coordinates the shared #829/#831 protected local store, legacy migration,
/// and reconnect replay for one explicit Account + Person + environment scope.
///
/// Product code must never infer Person from Account. Callers obtain the
/// canonical self Person from lifemate-api (for example the capabilities read
/// model) and provide it through [namespace].
final class LifeMateSharedOfflineRuntime {
  LifeMateSharedOfflineRuntime._({
    required LifeMateLocalHealthStore store,
    required LifeMateLocalNamespace namespace,
    required LifeMateLocalMutationOutbox outbox,
    required LifeMateLocalMutationReplayEngine replayEngine,
    required LifeMateHttpMutationReplayTransport transport,
    required LifeMateLegacyMutationImporter legacyImporter,
    required String timeZone,
    required Set<String> legacyAccountIds,
    required bool ownsStore,
  }) : _store = store,
       _namespace = namespace,
       _outbox = outbox,
       _replayEngine = replayEngine,
       _transport = transport,
       _legacyImporter = legacyImporter,
       _timeZone = timeZone,
       _legacyAccountIds = Set<String>.unmodifiable(legacyAccountIds),
       _ownsStore = ownsStore;

  final LifeMateLocalHealthStore _store;
  final LifeMateLocalNamespace _namespace;
  final LifeMateLocalMutationOutbox _outbox;
  final LifeMateLocalMutationReplayEngine _replayEngine;
  final LifeMateHttpMutationReplayTransport _transport;
  final LifeMateLegacyMutationImporter _legacyImporter;
  final String _timeZone;
  final Set<String> _legacyAccountIds;
  final bool _ownsStore;
  bool _closed = false;

  LifeMateLocalNamespace get namespace => _namespace;

  /// Opens the shared encrypted local database, losslessly imports compatible
  /// pre-#831 queued dose actions, then returns a runtime ready for bounded
  /// replay. No network request is made by initialization itself.
  static Future<LifeMateSharedOfflineRuntime> open({
    required LifeMateLocalNamespace namespace,
    required String timeZone,
    required Uri apiBaseUri,
    required AccessTokenProvider accessToken,
    Set<String> legacyAccountIds = const <String>{},
    LifeMateLocalHealthStore? store,
    LifeMateMutationStorage? legacyStorage,
    http.Client? httpClient,
    int maximumMutationsPerRun = 25,
    DateTime Function()? now,
  }) async {
    final normalizedTimeZone = timeZone.trim();
    if (normalizedTimeZone.isEmpty) {
      throw ArgumentError.value(timeZone, 'timeZone');
    }
    final normalizedLegacyAccountIds = legacyAccountIds
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();

    final ownsStore = store == null;
    final localStore =
        store ?? await LifeMateLocalHealthStore.openDefault(now: now);
    final outbox = LifeMateLocalMutationOutbox(store: localStore, now: now);
    final transport = LifeMateHttpMutationReplayTransport(
      apiBaseUri: apiBaseUri,
      accessToken: accessToken,
      httpClient: httpClient,
    );
    final importer = LifeMateLegacyMutationImporter(
      outbox: outbox,
      apiBaseUri: apiBaseUri,
      legacyStorage: legacyStorage,
    );

    try {
      await importer.importPending(
        namespace: namespace,
        timeZone: normalizedTimeZone,
        legacyAccountIds: normalizedLegacyAccountIds,
      );

      return LifeMateSharedOfflineRuntime._(
        store: localStore,
        namespace: namespace,
        outbox: outbox,
        replayEngine: LifeMateLocalMutationReplayEngine(
          outbox: outbox,
          transport: transport,
          maximumMutationsPerRun: maximumMutationsPerRun,
          now: now,
        ),
        transport: transport,
        legacyImporter: importer,
        timeZone: normalizedTimeZone,
        legacyAccountIds: normalizedLegacyAccountIds,
        ownsStore: ownsStore,
      );
    } catch (_) {
      transport.close();
      if (ownsStore) localStore.close();
      rethrow;
    }
  }

  /// Imports any compatible actions accepted by the transitional legacy write
  /// capture after this runtime was opened. Import is lossless: the legacy copy
  /// is deleted only after the shared outbox has durably persisted it.
  Future<int> importLegacyPending() async {
    _requireOpen();
    return _legacyImporter.importPending(
      namespace: _namespace,
      timeZone: _timeZone,
      legacyAccountIds: _legacyAccountIds,
    );
  }

  /// Replays only eligible actions for this runtime's explicit namespace.
  /// The returned value remains low-cardinality and PHI-free.
  Future<LifeMateOfflineSyncResult> flushDetailed() async {
    _requireOpen();
    await importLegacyPending();
    final result = await _replayEngine.replayEligible(namespace: _namespace);
    return LifeMateOfflineSyncResult(
      replayed: result.confirmed,
      conflicts: result.conflicts,
      terminalRejected: result.rejected,
      retainedForRetry: result.retainedForRetry,
      pendingRemaining: result.remaining,
    );
  }

  Future<int> pendingMutationCount() async {
    _requireOpen();
    await importLegacyPending();
    final mutations = await _outbox.list(namespace: _namespace);
    return mutations.where(_isPendingForReplay).length;
  }

  /// Returns only local adherence presentation state needed to preserve the
  /// existing pending-dose overlay while WellMate migrates away from the legacy
  /// queue. Keys are occurrence IDs already known to the owning screen; no
  /// identifiers are logged or emitted to analytics by this runtime.
  Future<Map<String, String>> pendingAdherenceStates() async {
    _requireOpen();
    await importLegacyPending();
    final mutations = await _outbox.list(namespace: _namespace);
    final result = <String, String>{};
    for (final mutation in mutations) {
      if (mutation.domain != LifeMateMutationDomain.adherence ||
          !_isPendingForReplay(mutation)) {
        continue;
      }
      final status = mutation.payload['status']?.toString().toLowerCase();
      if (status != 'taken' && status != 'skipped') continue;
      result[mutation.sourceKey] = status!;
    }
    return result;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _transport.close();
    if (_ownsStore) _store.close();
  }

  void _requireOpen() {
    if (_closed) throw StateError('LifeMate shared offline runtime is closed.');
  }

  static bool _isPendingForReplay(LifeMateDurableMutation mutation) =>
      mutation.state == LifeMateMutationSyncState.pending ||
      mutation.state == LifeMateMutationSyncState.retryScheduled;
}
