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
    String mutationId = 'mutation-1',
    LifeMateMutationDomain domain = LifeMateMutationDomain.adherence,
    String sourceKey = 'dose-occurrence-1',
    String status = 'taken',
  }) => LifeMateDurableMutation(
    mutationId: mutationId,
    domain: domain,
    sourceKey: sourceKey,
    method: 'POST',
    endpointPath: '/api/v1/dose-occurrences/example/report',
    payload: <String, dynamic>{'clientRequestId': mutationId, 'status': status},
    createdAtUtc: DateTime.utc(2026, 9, 5, 1),
    timeZone: 'Asia/Tehran',
    expectedRevision: '7',
  );

  test(
    'outbox is person isolated and duplicate mutation id is idempotent',
    () async {
      final database = sqlite3.openInMemory();
      final store = LifeMateLocalHealthStore.forTesting(
        database: database,
        keyBytes: key,
      );
      final outbox = LifeMateLocalMutationOutbox(store: store);
      final original = mutation();

      expect(
        (await outbox.enqueue(
          namespace: namespace,
          mutation: original,
        )).mutationId,
        original.mutationId,
      );
      expect(
        (await outbox.enqueue(
          namespace: namespace,
          mutation: original,
        )).mutationId,
        original.mutationId,
      );
      expect(await outbox.list(namespace: namespace), hasLength(1));

      final otherPerson = LifeMateLocalNamespace(
        environmentId: 'test-environment',
        accountId: 'account-a',
        personId: 'person-b',
      );
      expect(await outbox.list(namespace: otherPerson), isEmpty);
      store.close();
    },
  );

  test('same id cannot be reused for a different logical action', () async {
    final database = sqlite3.openInMemory();
    final store = LifeMateLocalHealthStore.forTesting(
      database: database,
      keyBytes: key,
    );
    final outbox = LifeMateLocalMutationOutbox(store: store);
    await outbox.enqueue(namespace: namespace, mutation: mutation());

    await expectLater(
      outbox.enqueue(
        namespace: namespace,
        mutation: mutation(status: 'skipped'),
      ),
      throwsStateError,
    );
    store.close();
  });

  test(
    'retry state uses bounded backoff and survives in protected projection',
    () async {
      final database = sqlite3.openInMemory();
      final now = DateTime.utc(2026, 9, 5, 1);
      final store = LifeMateLocalHealthStore.forTesting(
        database: database,
        keyBytes: key,
        now: () => now,
      );
      final outbox = LifeMateLocalMutationOutbox(store: store, now: () => now);
      await outbox.enqueue(namespace: namespace, mutation: mutation());

      final retry = await outbox.markRetry(
        namespace: namespace,
        mutationId: 'mutation-1',
        errorClass: LifeMateMutationErrorClass.transport,
      );
      expect(retry.state, LifeMateMutationSyncState.retryScheduled);
      expect(retry.attemptCount, 1);
      expect(retry.nextAttemptAtUtc, now.add(const Duration(seconds: 15)));
      expect(await outbox.eligible(namespace: namespace, atUtc: now), isEmpty);
      expect(
        await outbox.eligible(
          namespace: namespace,
          atUtc: now.add(const Duration(seconds: 15)),
        ),
        hasLength(1),
      );
      expect(
        LifeMateLocalMutationOutbox.retryDelayForAttempt(99),
        const Duration(minutes: 15),
      );
      store.close();
    },
  );

  test('409 conflict remains durable for explicit domain resolution', () async {
    final database = sqlite3.openInMemory();
    final store = LifeMateLocalHealthStore.forTesting(
      database: database,
      keyBytes: key,
    );
    final outbox = LifeMateLocalMutationOutbox(store: store);
    await outbox.enqueue(
      namespace: namespace,
      mutation: mutation(
        domain: LifeMateMutationDomain.pregnancyDating,
        sourceKey: 'episode-1',
      ),
    );

    final conflict = await outbox.markConflict(
      namespace: namespace,
      mutationId: 'mutation-1',
    );
    expect(conflict.state, LifeMateMutationSyncState.conflict);
    expect(
      conflict.conflictPolicy,
      LifeMateMutationConflictPolicy.neverSilentLastWriteWins,
    );
    expect(await outbox.list(namespace: namespace), hasLength(1));
    expect(await outbox.eligible(namespace: namespace), isEmpty);
    store.close();
  });

  test('acknowledgement removes exactly one logical mutation', () async {
    final database = sqlite3.openInMemory();
    final store = LifeMateLocalHealthStore.forTesting(
      database: database,
      keyBytes: key,
    );
    final outbox = LifeMateLocalMutationOutbox(store: store);
    await outbox.enqueue(namespace: namespace, mutation: mutation());
    await outbox.enqueue(
      namespace: namespace,
      mutation: mutation(
        mutationId: 'mutation-2',
        sourceKey: 'dose-occurrence-2',
      ),
    );

    final acknowledged = await outbox.acknowledge(
      namespace: namespace,
      mutationId: 'mutation-1',
    );
    expect(acknowledged?.mutationId, 'mutation-1');
    expect(
      (await outbox.list(
        namespace: namespace,
      )).map((value) => value.mutationId),
      <String>['mutation-2'],
    );
    store.close();
  });

  test('conflict policies are explicit for every health domain', () {
    expect(
      lifeMateConflictPolicyFor(LifeMateMutationDomain.adherence),
      LifeMateMutationConflictPolicy.idempotentLogicalEvent,
    );
    expect(
      lifeMateConflictPolicyFor(LifeMateMutationDomain.treatment),
      LifeMateMutationConflictPolicy.explicitVersionResolution,
    );
    expect(
      lifeMateConflictPolicyFor(LifeMateMutationDomain.careEvent),
      LifeMateMutationConflictPolicy.explicitVersionResolution,
    );
    expect(
      lifeMateConflictPolicyFor(LifeMateMutationDomain.womenHealth),
      LifeMateMutationConflictPolicy.deduplicateAndMerge,
    );
    expect(
      lifeMateConflictPolicyFor(LifeMateMutationDomain.pregnancyDating),
      LifeMateMutationConflictPolicy.neverSilentLastWriteWins,
    );
    expect(
      lifeMateConflictPolicyFor(LifeMateMutationDomain.healthObservation),
      LifeMateMutationConflictPolicy.deduplicateAndMerge,
    );
    expect(
      lifeMateConflictPolicyFor(LifeMateMutationDomain.sharedAuthorization),
      LifeMateMutationConflictPolicy.authorizationFailClosed,
    );
  });

  test(
    'outbox refuses absolute endpoints so old origins are never persisted',
    () {
      expect(
        () => LifeMateDurableMutation(
          mutationId: 'mutation-1',
          domain: LifeMateMutationDomain.adherence,
          sourceKey: 'dose-1',
          method: 'POST',
          endpointPath: 'https://old-api.example.test/api/v1/report',
          payload: const <String, dynamic>{},
          createdAtUtc: DateTime.utc(2026, 9, 5),
          timeZone: 'UTC',
        ),
        throwsArgumentError,
      );
    },
  );
}
