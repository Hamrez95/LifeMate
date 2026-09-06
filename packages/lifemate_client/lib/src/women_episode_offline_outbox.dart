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
  }) : _store = store,
       _namespace = namespace,
       _timeZone = timeZone,
       _outbox = LifeMateLocalMutationOutbox(store: store);

  final LifeMateLocalHealthStore _store;
  final LifeMateLocalNamespace _namespace;
  final String _timeZone;
  final LifeMateLocalMutationOutbox _outbox;
  bool _closed = false;

  static Future<WomenEpisodeOfflineOutbox> openDefault({
    required LifeMateLocalNamespace namespace,
    required String timeZone,
  }) async {
    final normalizedTimeZone = timeZone.trim();
    if (normalizedTimeZone.isEmpty) {
      throw ArgumentError.value(timeZone, 'timeZone');
    }
    final store = await LifeMateLocalHealthStore.openDefault();
    return WomenEpisodeOfflineOutbox._(
      store: store,
      namespace: namespace,
      timeZone: normalizedTimeZone,
    );
  }

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
    _store.close();
  }

  void _requireOpen() {
    if (_closed) throw StateError('Women episode offline outbox is closed.');
  }
}
