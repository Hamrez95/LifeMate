import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_core/lifemate_core.dart';

void main() {
  test('builds a private period create', () {
    final mutation = LifeMateOfflineWomenEpisodeMutation.buildCreate(
      mutationId: 'women-episode-create-0001',
      startedOn: DateTime(2026, 9, 6, 22, 30),
      privateNotes: ' owner only ',
      timeZone: 'Asia/Tehran',
      createdAtUtc: DateTime.utc(2026, 9, 6, 4),
    );

    expect(mutation.domain, LifeMateMutationDomain.womenHealth);
    expect(mutation.method, 'POST');
    expect(mutation.endpointPath, '/api/v1/women-calendar/episodes');
    expect(mutation.payload['startedOn'], '2026-09-06');
    expect(mutation.payload['endedOn'], isNull);
    expect(mutation.payload['privateNotes'], 'owner only');
    expect(mutation.expectedRevision, isNull);
    expect(mutation.payload.containsKey('relationshipId'), isFalse);
  });

  test('builds a revision-bound period update', () {
    final mutation = LifeMateOfflineWomenEpisodeMutation.buildUpdate(
      mutationId: 'women-episode-update-0001',
      episodeId: 'episode_123',
      version: 4,
      startedOn: DateTime(2026, 9, 3),
      endedOn: DateTime(2026, 9, 6),
      privateNotes: '',
      timeZone: 'Asia/Tehran',
      createdAtUtc: DateTime.utc(2026, 9, 6, 4),
    );

    expect(mutation.method, 'PATCH');
    expect(mutation.sourceKey, 'women-episode:episode_123');
    expect(mutation.expectedRevision, '4');
    expect(mutation.payload['version'], 4);
    expect(mutation.payload['endedOn'], '2026-09-06');
    expect(mutation.payload['privateNotes'], isNull);
  });

  test('rejects unsafe create input', () {
    expect(
      () => LifeMateOfflineWomenEpisodeMutation.buildCreate(
        mutationId: 'short',
        startedOn: DateTime(2026, 9, 6),
        timeZone: 'Asia/Tehran',
      ),
      throwsArgumentError,
    );
    expect(
      () => LifeMateOfflineWomenEpisodeMutation.buildCreate(
        mutationId: 'women-episode-create-0002',
        startedOn: DateTime(2026, 9, 6),
        endedOn: DateTime(2026, 9, 5),
        timeZone: 'Asia/Tehran',
      ),
      throwsArgumentError,
    );
  });

  test('rejects unsafe update input', () {
    expect(
      () => LifeMateOfflineWomenEpisodeMutation.buildUpdate(
        mutationId: 'women-episode-update-0002',
        episodeId: '../episode',
        version: 1,
        startedOn: DateTime(2026, 9, 6),
        timeZone: 'Asia/Tehran',
      ),
      throwsArgumentError,
    );
    expect(
      () => LifeMateOfflineWomenEpisodeMutation.buildUpdate(
        mutationId: 'women-episode-update-0003',
        episodeId: 'episode_123',
        version: 0,
        startedOn: DateTime(2026, 9, 6),
        timeZone: 'Asia/Tehran',
      ),
      throwsArgumentError,
    );
  });
}
