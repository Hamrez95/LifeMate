import 'package:lifemate_client/lifemate_client.dart';

final class WomenEpisodeOfflineBridge {
  WomenEpisodeOfflineBridge._();

  static Future<WomenEpisodeOfflineBridge> open({
    required LifeMateApiClient apiClient,
  }) =>
      throw UnsupportedError(
        'Protected Women episode persistence is unavailable on web.',
      );

  Future<void> enqueueCreate({
    required String mutationId,
    required DateTime startedOn,
    DateTime? endedOn,
    String? privateNotes,
  }) =>
      throw UnsupportedError(
        'Protected Women episode persistence is unavailable on web.',
      );

  Future<void> coalescePendingCreate({
    required String mutationId,
    required DateTime startedOn,
    DateTime? endedOn,
    String? privateNotes,
  }) =>
      throw UnsupportedError(
        'Protected Women episode persistence is unavailable on web.',
      );

  Future<void> cancelPendingCreate({required String mutationId}) =>
      throw UnsupportedError(
        'Protected Women episode persistence is unavailable on web.',
      );

  Future<void> enqueueUpdate({
    required String mutationId,
    required String episodeId,
    required int version,
    required DateTime startedOn,
    DateTime? endedOn,
    String? privateNotes,
  }) =>
      throw UnsupportedError(
        'Protected Women episode persistence is unavailable on web.',
      );

  Future<List<Map<String, dynamic>>> project(
    Iterable<Map<String, dynamic>> serverEpisodes,
  ) =>
      Future<List<Map<String, dynamic>>>.value(
        serverEpisodes
            .map((episode) => Map<String, dynamic>.from(episode))
            .toList(growable: false),
      );

  Future<Object?> flush() => Future<Object?>.value();

  void close() {}
}
