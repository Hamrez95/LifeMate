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
}
