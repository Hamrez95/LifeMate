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

  test('pending create projects without fabricating canonical episode identity', () async {
    final store = LifeMateLocalHealthStore.forTesting(
      database: sqlite3.openInMemory(),
      keyBytes: key,
    );
    final adapter = WomenEpisodeOfflineOutbox.forTesting(
      store: store,
      namespace: owner,
      timeZone: 'Asia/Tehran',
    );
    final otherAdapter = WomenEpisodeOfflineOutbox.forTesting(
      store: store,
      namespace: otherPerson,
      timeZone: 'Asia/Tehran',
    );
    addTearDown(() {
      adapter.close();
      otherAdapter.close();
      store.close();
    });

    await adapter.enqueueCreate(
      mutationId: 'women-episode-client-pending-0001',
      startedOn: DateTime(2026, 9, 7),
      privateNotes: 'owner private note',
      createdAtUtc: DateTime.utc(2026, 9, 6, 20),
    );

    final rows = await adapter.pendingCreates();
    expect(rows, hasLength(1));
    final row = rows.single;
    expect(row['clientRequestId'], 'women-episode-client-pending-0001');
    expect(row['startedOn'], '2026-09-07');
    expect(row['pendingSync'], isTrue);
    expect(row['syncState'], 'pending');
    expect(row['canEditLocally'], isTrue);
    expect(row.containsKey('id'), isFalse);
    expect(row.containsKey('version'), isFalse);
    expect(await otherAdapter.pendingCreates(), isEmpty);
  });

  test('retrying create remains visible but cannot be locally coalesced', () async {
    final now = DateTime.utc(2026, 9, 6, 21);
    final store = LifeMateLocalHealthStore.forTesting(
      database: sqlite3.openInMemory(),
      keyBytes: key,
      now: () => now,
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
      mutationId: 'women-episode-client-pending-0002',
      startedOn: DateTime(2026, 9, 5),
      createdAtUtc: now.subtract(const Duration(hours: 1)),
    );
    await LifeMateLocalMutationOutbox(store: store, now: () => now).markRetry(
      namespace: owner,
      mutationId: 'women-episode-client-pending-0002',
      errorClass: LifeMateMutationErrorClass.transport,
    );

    final rows = await adapter.pendingCreates();
    expect(rows, hasLength(1));
    expect(rows.single['syncState'], 'retry_scheduled');
    expect(rows.single['canEditLocally'], isFalse);
  });

  test('canonical update mutations are not exposed as pending creates', () async {
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
      mutationId: 'women-episode-client-update-0001',
      episodeId: 'episode-server-1',
      version: 4,
      startedOn: DateTime(2026, 9, 1),
      endedOn: DateTime(2026, 9, 6),
      createdAtUtc: DateTime.utc(2026, 9, 6, 20),
    );

    expect(await adapter.pendingCreates(), isEmpty);
  });
}
