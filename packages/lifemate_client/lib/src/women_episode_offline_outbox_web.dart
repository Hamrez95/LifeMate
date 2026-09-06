import 'package:lifemate_core/lifemate_core.dart';

/// Browser stub: protected health outbox persistence deliberately remains
/// native-only instead of falling back to an unencrypted browser store.
final class WomenEpisodeOfflineOutbox {
  const WomenEpisodeOfflineOutbox._();

  static Future<WomenEpisodeOfflineOutbox> openDefault({
    required LifeMateLocalNamespace namespace,
    required String timeZone,
  }) => Future<WomenEpisodeOfflineOutbox>.error(_unsupported());

  static WomenEpisodeOfflineOutbox forTesting({
    required LifeMateLocalHealthStore store,
    required LifeMateLocalNamespace namespace,
    required String timeZone,
  }) => throw _unsupported();

  Future<void> enqueueCreate({
    required String mutationId,
    required DateTime startedOn,
    DateTime? endedOn,
    String? privateNotes,
    DateTime? createdAtUtc,
  }) => Future<void>.error(_unsupported());

  Future<void> coalescePendingCreate({
    required String mutationId,
    required DateTime startedOn,
    DateTime? endedOn,
    String? privateNotes,
  }) => Future<void>.error(_unsupported());

  Future<void> enqueueUpdate({
    required String mutationId,
    required String episodeId,
    required int version,
    required DateTime startedOn,
    DateTime? endedOn,
    String? privateNotes,
    DateTime? createdAtUtc,
  }) => Future<void>.error(_unsupported());

  void close() {}

  static UnsupportedError _unsupported() => UnsupportedError(
    'Protected offline health execution is unavailable on web.',
  );
}
