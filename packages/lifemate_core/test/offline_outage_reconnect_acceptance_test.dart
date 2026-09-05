import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_core/lifemate_core.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  final key = List<int>.generate(32, (index) => index + 1);
  final namespace = LifeMateLocalNamespace(
    environmentId: 'test-environment',
    accountId: 'account-a',
    personId: 'person-a',
  );

  LifeMateDurableMutation mutation(String id) => LifeMateDurableMutation(
    mutationId: id,
    domain: LifeMateMutationDomain.adherence,
    sourceKey: 'dose-$id',
    method: 'POST',
    endpointPath: '/api/v1/dose-occurrences/$id/report',
    payload: <String, dynamic>{'clientRequestId': id, 'status': 'taken'},
    createdAtUtc: DateTime.utc(2026, 9, 5, 2),
    timeZone: 'Asia/Tehran',
  );

  test(
    'process restart plus 24h outage retains and replays every accepted owner action',
    () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'lifemate-offline-03-',
      );
      addTearDown(() async {
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      });
      final databasePath = '${tempDirectory.path}/health.db';
      var now = DateTime.utc(2026, 9, 5, 2);

      final firstStore = LifeMateLocalHealthStore.forTesting(
        database: sqlite3.open(databasePath),
        keyBytes: key,
        now: () => now,
      );
      final firstOutbox = LifeMateLocalMutationOutbox(
        store: firstStore,
        now: () => now,
      );
      await firstOutbox.enqueue(
        namespace: namespace,
        mutation: mutation('owner-action-a'),
      );
      await firstOutbox.enqueue(
        namespace: namespace,
        mutation: mutation('owner-action-b'),
      );

      final outage = await LifeMateLocalMutationReplayEngine(
        outbox: firstOutbox,
        transport: const _OfflineTransport(),
        now: () => now,
      ).replayEligible(namespace: namespace);

      expect(outage.confirmed, 0);
      expect(outage.retainedForRetry, 1);
      expect(outage.remaining, 2);
      expect(
        (await firstOutbox.get(
          namespace: namespace,
          mutationId: 'owner-action-a',
        ))?.state,
        LifeMateMutationSyncState.retryScheduled,
      );
      expect(
        (await firstOutbox.get(
          namespace: namespace,
          mutationId: 'owner-action-b',
        ))?.state,
        LifeMateMutationSyncState.pending,
      );
      firstStore.close();

      // Simulate the app process being gone throughout a full-day network outage.
      now = now.add(const Duration(hours: 24));
      final reopenedStore = LifeMateLocalHealthStore.forTesting(
        database: sqlite3.open(databasePath),
        keyBytes: key,
        now: () => now,
      );
      addTearDown(reopenedStore.close);
      final reopenedOutbox = LifeMateLocalMutationOutbox(
        store: reopenedStore,
        now: () => now,
      );

      final retainedIds = (await reopenedOutbox.list(
        namespace: namespace,
      )).map((value) => value.mutationId).toList(growable: false);
      expect(retainedIds, <String>['owner-action-a', 'owner-action-b']);

      final transport = _SuccessfulTransport();
      final reconnect = await LifeMateLocalMutationReplayEngine(
        outbox: reopenedOutbox,
        transport: transport,
        now: () => now,
      ).replayEligible(namespace: namespace);

      expect(reconnect.confirmed, 2);
      expect(reconnect.remaining, 0);
      expect(transport.sentIds, <String>['owner-action-a', 'owner-action-b']);
      expect(await reopenedOutbox.list(namespace: namespace), isEmpty);
    },
  );
}

final class _OfflineTransport implements LifeMateMutationReplayTransport {
  const _OfflineTransport();

  @override
  Future<LifeMateMutationReplayResponse> send(
    LifeMateDurableMutation mutation,
  ) {
    throw const LifeMateMutationReplayTransportException();
  }
}

final class _SuccessfulTransport implements LifeMateMutationReplayTransport {
  final List<String> sentIds = <String>[];

  @override
  Future<LifeMateMutationReplayResponse> send(
    LifeMateDurableMutation mutation,
  ) async {
    sentIds.add(mutation.mutationId);
    return const LifeMateMutationReplayResponse(200);
  }
}
