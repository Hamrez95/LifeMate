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

  LifeMateDurableMutation mutation({
    required String id,
    LifeMateMutationDomain domain = LifeMateMutationDomain.adherence,
  }) => LifeMateDurableMutation(
    mutationId: id,
    domain: domain,
    sourceKey: 'source-$id',
    method: 'POST',
    endpointPath: '/api/v1/test/$id',
    payload: <String, dynamic>{'clientRequestId': id},
    createdAtUtc: DateTime.utc(2026, 9, 5, 2),
    timeZone: 'Asia/Tehran',
  );

  test('2xx acknowledges exactly the replayed logical mutation', () async {
    final database = sqlite3.openInMemory();
    final store = LifeMateLocalHealthStore.forTesting(
      database: database,
      keyBytes: key,
    );
    final outbox = LifeMateLocalMutationOutbox(store: store);
    await outbox.enqueue(
      namespace: namespace,
      mutation: mutation(id: 'a'),
    );
    await outbox.enqueue(
      namespace: namespace,
      mutation: mutation(id: 'b'),
    );

    final transport = _FakeTransport(<int>[200, 204]);
    final result = await LifeMateLocalMutationReplayEngine(
      outbox: outbox,
      transport: transport,
    ).replayEligible(namespace: namespace);

    expect(result.confirmed, 2);
    expect(result.remaining, 0);
    expect(await outbox.list(namespace: namespace), isEmpty);
    expect(transport.sentIds, <String>['a', 'b']);
    store.close();
  });

  test(
    '409 keeps pregnancy dating conflict durable and never applies LWW',
    () async {
      final database = sqlite3.openInMemory();
      final store = LifeMateLocalHealthStore.forTesting(
        database: database,
        keyBytes: key,
      );
      final outbox = LifeMateLocalMutationOutbox(store: store);
      await outbox.enqueue(
        namespace: namespace,
        mutation: mutation(
          id: 'pregnancy-revision',
          domain: LifeMateMutationDomain.pregnancyDating,
        ),
      );

      final result = await LifeMateLocalMutationReplayEngine(
        outbox: outbox,
        transport: _FakeTransport(<int>[409]),
      ).replayEligible(namespace: namespace);

      expect(result.conflicts, 1);
      expect(result.confirmed, 0);
      final retained = await outbox.get(
        namespace: namespace,
        mutationId: 'pregnancy-revision',
      );
      expect(retained?.state, LifeMateMutationSyncState.conflict);
      expect(
        retained?.conflictPolicy,
        LifeMateMutationConflictPolicy.neverSilentLastWriteWins,
      );
      store.close();
    },
  );

  test(
    'auth failure is retained with backoff and stops the replay run',
    () async {
      final database = sqlite3.openInMemory();
      final now = DateTime.utc(2026, 9, 5, 2);
      final store = LifeMateLocalHealthStore.forTesting(
        database: database,
        keyBytes: key,
        now: () => now,
      );
      final outbox = LifeMateLocalMutationOutbox(store: store, now: () => now);
      await outbox.enqueue(
        namespace: namespace,
        mutation: mutation(id: 'a'),
      );
      await outbox.enqueue(
        namespace: namespace,
        mutation: mutation(id: 'b'),
      );
      final transport = _FakeTransport(<int>[401, 200]);

      final result = await LifeMateLocalMutationReplayEngine(
        outbox: outbox,
        transport: transport,
        now: () => now,
      ).replayEligible(namespace: namespace);

      expect(result.retainedForRetry, 1);
      expect(result.remaining, 2);
      expect(transport.sentIds, <String>['a']);
      final retained = await outbox.get(namespace: namespace, mutationId: 'a');
      expect(retained?.errorClass, LifeMateMutationErrorClass.authentication);
      expect(retained?.state, LifeMateMutationSyncState.retryScheduled);
      expect(retained?.nextAttemptAtUtc, now.add(const Duration(seconds: 15)));
      store.close();
    },
  );

  test('429 is retained and does not create a tight retry loop', () async {
    final database = sqlite3.openInMemory();
    final store = LifeMateLocalHealthStore.forTesting(
      database: database,
      keyBytes: key,
    );
    final outbox = LifeMateLocalMutationOutbox(store: store);
    await outbox.enqueue(
      namespace: namespace,
      mutation: mutation(id: 'a'),
    );

    final result = await LifeMateLocalMutationReplayEngine(
      outbox: outbox,
      transport: _FakeTransport(<int>[429]),
    ).replayEligible(namespace: namespace);

    expect(result.retainedForRetry, 1);
    final retained = await outbox.get(namespace: namespace, mutationId: 'a');
    expect(retained?.errorClass, LifeMateMutationErrorClass.throttled);
    store.close();
  });

  test(
    'terminal 4xx becomes explicit rejected state and replay continues',
    () async {
      final database = sqlite3.openInMemory();
      final store = LifeMateLocalHealthStore.forTesting(
        database: database,
        keyBytes: key,
      );
      final outbox = LifeMateLocalMutationOutbox(store: store);
      await outbox.enqueue(
        namespace: namespace,
        mutation: mutation(id: 'a'),
      );
      await outbox.enqueue(
        namespace: namespace,
        mutation: mutation(id: 'b'),
      );
      final transport = _FakeTransport(<int>[422, 200]);

      final result = await LifeMateLocalMutationReplayEngine(
        outbox: outbox,
        transport: transport,
      ).replayEligible(namespace: namespace);

      expect(result.rejected, 1);
      expect(result.confirmed, 1);
      expect(result.remaining, 0);
      final rejected = await outbox.get(namespace: namespace, mutationId: 'a');
      expect(rejected?.state, LifeMateMutationSyncState.rejected);
      expect(rejected?.errorClass, LifeMateMutationErrorClass.clientRejected);
      expect(await outbox.get(namespace: namespace, mutationId: 'b'), isNull);
      store.close();
    },
  );

  test(
    'typed transport failure is retained but unexpected failures surface',
    () async {
      final database = sqlite3.openInMemory();
      final store = LifeMateLocalHealthStore.forTesting(
        database: database,
        keyBytes: key,
      );
      final outbox = LifeMateLocalMutationOutbox(store: store);
      await outbox.enqueue(
        namespace: namespace,
        mutation: mutation(id: 'a'),
      );

      final retryResult = await LifeMateLocalMutationReplayEngine(
        outbox: outbox,
        transport: _ThrowingTransport(
          const LifeMateMutationReplayTransportException(),
        ),
      ).replayEligible(namespace: namespace);
      expect(retryResult.retainedForRetry, 1);
      expect(
        (await outbox.get(namespace: namespace, mutationId: 'a'))?.errorClass,
        LifeMateMutationErrorClass.transport,
      );

      await outbox.enqueue(
        namespace: namespace,
        mutation: mutation(id: 'b'),
      );
      await expectLater(
        LifeMateLocalMutationReplayEngine(
          outbox: outbox,
          transport: _ThrowingTransport(StateError('adapter bug')),
        ).replayEligible(namespace: namespace),
        throwsStateError,
      );
      expect(
        await outbox.get(namespace: namespace, mutationId: 'b'),
        isNotNull,
      );
      store.close();
    },
  );

  test('maximum per run bounds reconnect work', () async {
    final database = sqlite3.openInMemory();
    final store = LifeMateLocalHealthStore.forTesting(
      database: database,
      keyBytes: key,
    );
    final outbox = LifeMateLocalMutationOutbox(store: store);
    for (final id in <String>['a', 'b', 'c']) {
      await outbox.enqueue(
        namespace: namespace,
        mutation: mutation(id: id),
      );
    }
    final transport = _FakeTransport(<int>[200, 200, 200]);

    final result = await LifeMateLocalMutationReplayEngine(
      outbox: outbox,
      transport: transport,
      maximumMutationsPerRun: 2,
    ).replayEligible(namespace: namespace);

    expect(result.confirmed, 2);
    expect(result.remaining, 1);
    expect(transport.sentIds, <String>['a', 'b']);
    store.close();
  });
}

final class _FakeTransport implements LifeMateMutationReplayTransport {
  _FakeTransport(this.statuses);

  final List<int> statuses;
  final List<String> sentIds = <String>[];

  @override
  Future<LifeMateMutationReplayResponse> send(
    LifeMateDurableMutation mutation,
  ) async {
    sentIds.add(mutation.mutationId);
    final status = statuses[sentIds.length - 1];
    return LifeMateMutationReplayResponse(status);
  }
}

final class _ThrowingTransport implements LifeMateMutationReplayTransport {
  const _ThrowingTransport(this.error);

  final Object error;

  @override
  Future<LifeMateMutationReplayResponse> send(
    LifeMateDurableMutation mutation,
  ) async {
    throw error;
  }
}
