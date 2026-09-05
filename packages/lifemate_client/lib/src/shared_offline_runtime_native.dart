import 'package:http/http.dart' as http;
import 'package:lifemate_core/lifemate_core.dart';

import 'legacy_mutation_importer.dart';
import 'lifemate_api_client.dart' show AccessTokenProvider;
import 'mutation_replay_transport.dart';
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

  LifeMateLocalNamespace toLocalNamespace() => LifeMateLocalNamespace(
    environmentId: environmentId,
    accountId: accountId,
    personId: personId,
  );

  static LifeMateOfflineNamespace fromLocal(LifeMateLocalNamespace value) =>
      LifeMateOfflineNamespace(
        environmentId: value.environmentId,
        accountId: value.accountId,
        personId: value.personId,
      );

  static String _required(String value, String field) {
    final normalized = value.trim();
    if (normalized.isEmpty) throw ArgumentError.value(value, field);
    return normalized;
  }
}

/// Native shared #829/#831 protected local store, replay and server-projection
/// reconciliation runtime. Owner projections and pending local mutations share
/// one encrypted namespace while remaining in separate bounded domains.
final class LifeMateSharedOfflineRuntime {
  LifeMateSharedOfflineRuntime._({
    required LifeMateLocalHealthStore store,
    required LifeMateOfflineNamespace namespace,
    required LifeMateLocalNamespace localNamespace,
    required LifeMateLocalMutationOutbox outbox,
    required LifeMateLocalMutationReplayEngine replayEngine,
    required LifeMateLocalProjectionReconciler projectionReconciler,
    required LifeMateHttpMutationReplayTransport transport,
    required LifeMateLegacyMutationImporter legacyImporter,
    required String timeZone,
    required Set<String> legacyAccountIds,
    required bool ownsStore,
  }) : _store = store,
       _namespace = namespace,
       _localNamespace = localNamespace,
       _outbox = outbox,
       _replayEngine = replayEngine,
       _projectionReconciler = projectionReconciler,
       _transport = transport,
       _legacyImporter = legacyImporter,
       _timeZone = timeZone,
       _legacyAccountIds = Set<String>.unmodifiable(legacyAccountIds),
       _ownsStore = ownsStore;

  final LifeMateLocalHealthStore _store;
  final LifeMateOfflineNamespace _namespace;
  final LifeMateLocalNamespace _localNamespace;
  final LifeMateLocalMutationOutbox _outbox;
  final LifeMateLocalMutationReplayEngine _replayEngine;
  final LifeMateLocalProjectionReconciler _projectionReconciler;
  final LifeMateHttpMutationReplayTransport _transport;
  final LifeMateLegacyMutationImporter _legacyImporter;
  final String _timeZone;
  final Set<String> _legacyAccountIds;
  final bool _ownsStore;
  bool _closed = false;

  LifeMateOfflineNamespace get namespace => _namespace;

  static Future<LifeMateSharedOfflineRuntime> open({
    required Object namespace,
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
    final offlineNamespace = switch (namespace) {
      LifeMateOfflineNamespace value => value,
      LifeMateLocalNamespace value => LifeMateOfflineNamespace.fromLocal(value),
      _ => throw ArgumentError.value(namespace, 'namespace'),
    };
    final localNamespace = offlineNamespace.toLocalNamespace();
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
        namespace: localNamespace,
        timeZone: normalizedTimeZone,
        legacyAccountIds: normalizedLegacyAccountIds,
      );

      return LifeMateSharedOfflineRuntime._(
        store: localStore,
        namespace: offlineNamespace,
        localNamespace: localNamespace,
        outbox: outbox,
        replayEngine: LifeMateLocalMutationReplayEngine(
          outbox: outbox,
          transport: transport,
          maximumMutationsPerRun: maximumMutationsPerRun,
          now: now,
        ),
        projectionReconciler: LifeMateLocalProjectionReconciler(
          store: localStore,
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

  Future<int> importLegacyPending() async {
    _requireOpen();
    return _legacyImporter.importPending(
      namespace: _localNamespace,
      timeZone: _timeZone,
      legacyAccountIds: _legacyAccountIds,
    );
  }

  Future<LifeMateOfflineSyncResult> flushDetailed() async {
    _requireOpen();
    await importLegacyPending();
    final result = await _replayEngine.replayEligible(namespace: _localNamespace);
    return LifeMateOfflineSyncResult(
      replayed: result.confirmed,
      conflicts: result.conflicts,
      terminalRejected: result.rejected,
      retainedForRetry: result.retainedForRetry,
      pendingRemaining: result.remaining,
    );
  }

  /// Returns the encrypted checkpoint for the canonical owner care-event
  /// projection. The opaque cursor is never interpreted by the device.
  Future<LifeMateLocalSyncCheckpoint?> careEventCheckpoint() {
    _requireOpen();
    return _projectionReconciler.checkpoint(
      namespace: _localNamespace,
      domain: LifeMateLocalProjectionDomain.careEvent,
    );
  }

  /// Applies one canonical care-event pull page inside the same protected
  /// Account + Person + environment namespace as the outbox. Required side
  /// effects run before cursor acknowledgement, so failure keeps the old cursor
  /// and makes the page safely replayable after restart/reconnect.
  Future<LifeMateProjectionReconcileResult> applyCareEventPage({
    required LifeMateProjectionPullPage page,
    LifeMateBeforeProjectionCheckpoint? beforeCheckpoint,
  }) {
    _requireOpen();
    return _projectionReconciler.applyPage(
      namespace: _localNamespace,
      domain: LifeMateLocalProjectionDomain.careEvent,
      page: page,
      beforeCheckpoint: beforeCheckpoint,
    );
  }

  Future<int> pendingMutationCount() async {
    _requireOpen();
    await importLegacyPending();
    final mutations = await _outbox.list(namespace: _localNamespace);
    return mutations.where(_isPendingForReplay).length;
  }

  Future<Map<String, String>> pendingAdherenceStates() async {
    _requireOpen();
    await importLegacyPending();
    final mutations = await _outbox.list(namespace: _localNamespace);
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
