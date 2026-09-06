import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:lifemate_core/lifemate_core.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  final key = Uint8List.fromList(List<int>.generate(32, (index) => index + 1));
  final owner = LifeMateLocalNamespace(
    environmentId: 'production',
    accountId: 'account-a',
    personId: 'person-a',
  );
  final otherPerson = LifeMateLocalNamespace(
    environmentId: 'production',
    accountId: 'account-a',
    personId: 'person-b',
  );

  test('episode adapter writes only to the owner Person outbox', () async {
    final store = LifeMateLocalHealthStore.forTesting(
      database: sqlite3.openInMemory(),
      keyBytes: key,
    );
    final adapter = WomenEpisodeOfflineOutbox.forTesting(
      store: store,
      namespace: owner,
      timeZone: 'Asia/Tehran',
    );
    addTearDown(() {
      adapter.close();
      store.close();
    });

    await adapter.enqueueCreate(
      mutationId: 'women-episode-client-0001',
      startedOn: DateTime(2026, 9, 6),
      privateNotes: 'owner only',
      createdAtUtc: DateTime.utc(2026, 9, 6, 4),
    );

    final outbox = LifeMateLocalMutationOutbox(store: store);
    final stored = await outbox.get(
      namespace: owner,
      mutationId: 'women-episode-client-0001',
    );
    expect(stored, isNotNull);
    expect(stored!.endpointPath, '/api/v1/women-calendar/episodes');
    expect(stored.payload['privateNotes'], 'owner only');
    expect(stored.payload.containsKey('relationshipId'), isFalse);
    expect(await outbox.list(namespace: otherPerson), isEmpty);
  });

  test('episode adapter keeps server revision on updates', () async {
    final store = LifeMateLocalHealthStore.forTesting(
      database: sqlite3.openInMemory(),
      keyBytes: key,
    );
    final adapter = WomenEpisodeOfflineOutbox.forTesting(
      store: store,
      namespace: owner,
      timeZone: 'Asia/Tehran',
    );
    addTearDown(() {
      adapter.close();
      store.close();
    });

    await adapter.enqueueUpdate(
      mutationId: 'women-episode-client-0002',
      episodeId: 'episode_123',
      version: 7,
      startedOn: DateTime(2026, 9, 3),
      endedOn: DateTime(2026, 9, 6),
      createdAtUtc: DateTime.utc(2026, 9, 6, 4, 30),
    );

    final stored = await LifeMateLocalMutationOutbox(store: store).get(
      namespace: owner,
      mutationId: 'women-episode-client-0002',
    );
    expect(stored, isNotNull);
    expect(stored!.method, 'PATCH');
    expect(stored.expectedRevision, '7');
    expect(stored.payload['version'], 7);
    expect(stored.payload['endedOn'], '2026-09-06');
  });

  test('finishing an unsynced create keeps one POST with the same identity', () async {
    final store = LifeMateLocalHealthStore.forTesting(
      database: sqlite3.openInMemory(),
      keyBytes: key,
    );
    final adapter = WomenEpisodeOfflineOutbox.forTesting(
      store: store,
      namespace: owner,
      timeZone: 'Asia/Tehran',
    );
    addTearDown(() {
      adapter.close();
      store.close();
    });
    final outbox = LifeMateLocalMutationOutbox(store: store);
    final createdAt = DateTime.utc(2026, 9, 6, 5);

    await adapter.enqueueCreate(
      mutationId: 'women-episode-client-0003',
      startedOn: DateTime(2026, 9, 3),
      privateNotes: 'started offline',
      createdAtUtc: createdAt,
    );
    await adapter.coalescePendingCreate(
      mutationId: 'women-episode-client-0003',
      startedOn: DateTime(2026, 9, 3),
      endedOn: DateTime(2026, 9, 6),
      privateNotes: 'finished offline',
    );

    final items = await outbox.list(namespace: owner);
    expect(items, hasLength(1));
    final stored = items.single;
    expect(stored.mutationId, 'women-episode-client-0003');
    expect(stored.method, 'POST');
    expect(stored.endpointPath, '/api/v1/women-calendar/episodes');
    expect(stored.expectedRevision, isNull);
    expect(stored.createdAtUtc, createdAt);
    expect(stored.payload['startedOn'], '2026-09-03');
    expect(stored.payload['endedOn'], '2026-09-06');
    expect(stored.payload['privateNotes'], 'finished offline');
    expect(stored.payload.containsKey('version'), isFalse);
    expect(stored.endpointPath.contains('episode_'), isFalse);
    expect(await outbox.list(namespace: otherPerson), isEmpty);
  });

  test('coalescing fails closed once replay has started', () async {
    final store = LifeMateLocalHealthStore.forTesting(
      database: sqlite3.openInMemory(),
      keyBytes: key,
      now: () => DateTime.utc(2026, 9, 6, 6),
    );
    final adapter = WomenEpisodeOfflineOutbox.forTesting(
      store: store,
      namespace: owner,
      timeZone: 'Asia/Tehran',
    );
    addTearDown(() {
      adapter.close();
      store.close();
    });
    final outbox = LifeMateLocalMutationOutbox(
      store: store,
      now: () => DateTime.utc(2026, 9, 6, 6),
    );

    await adapter.enqueueCreate(
      mutationId: 'women-episode-client-0004',
      startedOn: DateTime(2026, 9, 3),
      createdAtUtc: DateTime.utc(2026, 9, 6, 5),
    );
    await outbox.markRetry(
      namespace: owner,
      mutationId: 'women-episode-client-0004',
      errorClass: LifeMateMutationErrorClass.transport,
    );

    await expectLater(
      adapter.coalescePendingCreate(
        mutationId: 'women-episode-client-0004',
        startedOn: DateTime(2026, 9, 3),
        endedOn: DateTime(2026, 9, 6),
      ),
      throwsStateError,
    );

    final stored = await outbox.get(
      namespace: owner,
      mutationId: 'women-episode-client-0004',
    );
    expect(stored, isNotNull);
    expect(stored!.state, LifeMateMutationSyncState.retryScheduled);
    expect(stored.attemptCount, 1);
    expect(stored.payload['endedOn'], isNull);
  });

  test('coalescing rejects a different mutation kind with the same ID', () async {
    final store = LifeMateLocalHealthStore.forTesting(
      database: sqlite3.openInMemory(),
      keyBytes: key,
    );
    final adapter = WomenEpisodeOfflineOutbox.forTesting(
      store: store,
      namespace: owner,
      timeZone: 'Asia/Tehran',
    );
    addTearDown(() {
      adapter.close();
      store.close();
    });
    final outbox = LifeMateLocalMutationOutbox(store: store);
    final foreign = LifeMateOfflineWomenEpisodeMutation.buildUpdate(
      mutationId: 'women-episode-client-0005',
      episodeId: 'episode_existing',
      version: 2,
      startedOn: DateTime(2026, 9, 2),
      timeZone: 'Asia/Tehran',
      createdAtUtc: DateTime.utc(2026, 9, 6, 5),
    );
    await outbox.enqueue(namespace: owner, mutation: foreign);

    await expectLater(
      adapter.coalescePendingCreate(
        mutationId: 'women-episode-client-0005',
        startedOn: DateTime(2026, 9, 2),
        endedOn: DateTime(2026, 9, 6),
      ),
      throwsStateError,
    );

    final stored = await outbox.get(
      namespace: owner,
      mutationId: 'women-episode-client-0005',
    );
    expect(stored, isNotNull);
    expect(stored!.method, 'PATCH');
    expect(stored.expectedRevision, '2');
  });
}
