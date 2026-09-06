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

  void _requireOpen() {
    if (_closed) throw StateError('Women episode offline outbox is closed.');
  }

  static String _normalizeTimeZone(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) throw ArgumentError.value(value, 'timeZone');
    return normalized;
  }
}
