import 'package:lifemate_core/lifemate_core.dart';

/// Native adapter for Women Health period-episode writes that reuses the
/// canonical encrypted local database and durable outbox from lifemate_core.
///
/// This is intentionally a narrow writer, not another scheduler/database or
/// sync engine. Authorization remains remote; only owner-local bounded episode
/// fields are persisted for later replay.
final class WomenEpisodeOfflineOutbox {
  WomenEpisodeOfflineOutbox._({
    required LifeMateLocalHealthStore store,
    required LifeMateLocalNamespace namespace,
    required String timeZone,
    required bool ownsStore,
  }) : _store = store,
       _namespace = namespace,
       _timeZone = timeZone,
       _ownsStore = ownsStore,
       _outbox = LifeMateLocalMutationOutbox(store: store);

  static const String _createEndpoint = '/api/v1/women-calendar/episodes';

  final LifeMateLocalHealthStore _store;
  final LifeMateLocalNamespace _namespace;
  final String _timeZone;
  final bool _ownsStore;
  final LifeMateLocalMutationOutbox _outbox;
  bool _closed = false;

  static Future<WomenEpisodeOfflineOutbox> openDefault({
    required LifeMateLocalNamespace namespace,
    required String timeZone,
  }) async {
    final normalizedTimeZone = _normalizeTimeZone(timeZone);
    final store = await LifeMateLocalHealthStore.openDefault();
    return WomenEpisodeOfflineOutbox._(
      store: store,
      namespace: namespace,
      timeZone: normalizedTimeZone,
      ownsStore: true,
    );
  }

  static WomenEpisodeOfflineOutbox forTesting({
    required LifeMateLocalHealthStore store,
    required LifeMateLocalNamespace namespace,
    required String timeZone,
  }) => WomenEpisodeOfflineOutbox._(
    store: store,
    namespace: namespace,
    timeZone: _normalizeTimeZone(timeZone),
    ownsStore: false,
  );

  Future<void> enqueueCreate({
    required String mutationId,
    required DateTime startedOn,
    DateTime? endedOn,
    String? privateNotes,
    DateTime? createdAtUtc,
  }) async {
    _requireOpen();
    await LifeMateOfflineWomenEpisodeMutation.enqueueCreate(
      outbox: _outbox,
      namespace: _namespace,
      mutationId: mutationId,
      startedOn: startedOn,
      endedOn: endedOn,
      privateNotes: privateNotes,
      timeZone: _timeZone,
      createdAtUtc: createdAtUtc,
    );
  }

  /// Replaces the payload of the same not-yet-attempted period CREATE with a
  /// newer bounded owner-private value while preserving its durable identity.
  ///
  /// This is the only safe pre-canonical "finish period" path: it deliberately
  /// keeps the original POST and mutation ID instead of inventing a server
  /// episode ID or queuing an invalid PATCH. Once replay has started, retrying
  /// or conflict handling owns the record and this operation fails closed.
  Future<void> coalescePendingCreate({
    required String mutationId,
    required DateTime startedOn,
    DateTime? endedOn,
    String? privateNotes,
  }) async {
    _requireOpen();
    final current = await _outbox.get(
      namespace: _namespace,
      mutationId: mutationId,
    );
    if (current == null) {
      throw StateError('Pending Women episode create was not found.');
    }
    if (!_isExactCreate(current)) {
      throw StateError('Mutation is not the matching Women episode create.');
    }
    if (current.state != LifeMateMutationSyncState.pending ||
        current.errorClass != LifeMateMutationErrorClass.none ||
        current.attemptCount != 0 ||
        current.nextAttemptAtUtc != null) {
      throw StateError(
        'A Women episode create cannot be changed after replay has started.',
      );
    }

    final replacement = LifeMateOfflineWomenEpisodeMutation.buildCreate(
      mutationId: current.mutationId,
      startedOn: startedOn,
      endedOn: endedOn,
      privateNotes: privateNotes,
      timeZone: current.timeZone,
      createdAtUtc: current.createdAtUtc,
    );
    if (replacement.domain != current.domain ||
        replacement.sourceKey != current.sourceKey ||
        replacement.method != current.method ||
        replacement.endpointPath != current.endpointPath ||
        replacement.expectedRevision != current.expectedRevision) {
      throw StateError('Women episode create identity changed unexpectedly.');
    }

    // One encrypted UPSERT replaces the exact outbox record. There is no
    // delete/re-enqueue window in which an accepted owner action can disappear.
    await _store.putProjection(
      namespace: _namespace,
      domain: LifeMateLocalProjectionDomain.pendingMutation,
      recordKey: current.mutationId,
      payload: replacement.toJson(),
      sourceRevision: replacement.expectedRevision,
      sourceUpdatedAtUtc: replacement.createdAtUtc,
    );
  }

  /// Returns only owner period CREATE intents that still participate in replay.
  /// No canonical server ID or version is fabricated; callers must keep these
  /// rows visually pending until authoritative refresh removes the outbox item.
  Future<List<Map<String, dynamic>>> pendingCreates() async {
    _requireOpen();
    final mutations = await _outbox.list(namespace: _namespace);
    final rows = <Map<String, dynamic>>[];
    for (final mutation in mutations) {
      if (mutation.domain != LifeMateMutationDomain.womenHealth ||
          !mutation.sourceKey.startsWith('women-episode-create:')) {
        continue;
      }
      if (!_isExactCreate(mutation)) {
        throw StateError('Malformed pending Women episode create encountered.');
      }
      if (mutation.state != LifeMateMutationSyncState.pending &&
          mutation.state != LifeMateMutationSyncState.retryScheduled) {
        continue;
      }
      rows.add(<String, dynamic>{
        'clientRequestId': mutation.mutationId,
        'startedOn': mutation.payload['startedOn'],
        'endedOn': mutation.payload['endedOn'],
        'privateNotes': mutation.payload['privateNotes'],
        'pendingSync': true,
        'syncState': mutation.state.wireName,
        'canEditLocally':
            mutation.state == LifeMateMutationSyncState.pending &&
            mutation.errorClass == LifeMateMutationErrorClass.none &&
            mutation.attemptCount == 0 &&
            mutation.nextAttemptAtUtc == null,
      });
    }
    rows.sort(
      (a, b) => (a['startedOn']?.toString() ?? '').compareTo(
        b['startedOn']?.toString() ?? '',
      ),
    );
    return List<Map<String, dynamic>>.unmodifiable(rows);
  }

  Future<void> enqueueUpdate({
    required String mutationId,
    required String episodeId,
    required int version,
    required DateTime startedOn,
    DateTime? endedOn,
    String? privateNotes,
    DateTime? createdAtUtc,
  }) async {
    _requireOpen();
    await LifeMateOfflineWomenEpisodeMutation.enqueueUpdate(
      outbox: _outbox,
      namespace: _namespace,
      mutationId: mutationId,
      episodeId: episodeId,
      version: version,
      startedOn: startedOn,
      endedOn: endedOn,
      privateNotes: privateNotes,
      timeZone: _timeZone,
      createdAtUtc: createdAtUtc,
    );
  }

  void close() {
    if (_closed) return;
    _closed = true;
    if (_ownsStore) _store.close();
  }

  bool _isExactCreate(LifeMateDurableMutation mutation) =>
      mutation.domain == LifeMateMutationDomain.womenHealth &&
      mutation.sourceKey == 'women-episode-create:${mutation.mutationId}' &&
      mutation.method == 'POST' &&
      mutation.endpointPath == _createEndpoint &&
      mutation.expectedRevision == null &&
      mutation.timeZone == _timeZone;

  void _requireOpen() {
    if (_closed) throw StateError('Women episode offline outbox is closed.');
  }

  static String _normalizeTimeZone(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) throw ArgumentError.value(value, 'timeZone');
    return normalized;
  }
}
