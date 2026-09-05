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

  LifeMateDurableMutation treatmentMutation(String id) =>
      LifeMateDurableMutation(
        mutationId: id,
        domain: LifeMateMutationDomain.treatment,
        sourceKey: 'treatment-episode-1',
        method: 'PATCH',
        endpointPath: '/api/v1/treatments/treatment-episode-1',
        payload: <String, dynamic>{'clientRequestId': id, 'schedule': '08:30'},
        createdAtUtc: DateTime.utc(2026, 9, 5, 3),
        timeZone: 'Asia/Tehran',
        expectedRevision: '7',
      );

  test(
    'offline multi-device treatment conflict remains durable for explicit resolution',
    () async {
      final database = sqlite3.openInMemory();
      final store = LifeMateLocalHealthStore.forTesting(
        database: database,
        keyBytes: key,
      );
      addTearDown(store.close);
      final outbox = LifeMateLocalMutationOutbox(store: store);
      await outbox.enqueue(
        namespace: namespace,
        mutation: treatmentMutation('treatment-edit-device-a'),
      );

      final result = await LifeMateLocalMutationReplayEngine(
        outbox: outbox,
        transport: const _StatusTransport(409),
      ).replayEligible(namespace: namespace);

      expect(result.confirmed, 0);
      expect(result.conflicts, 1);
      final retained = await outbox.get(
        namespace: namespace,
        mutationId: 'treatment-edit-device-a',
      );
      expect(retained, isNotNull);
      expect(retained?.state, LifeMateMutationSyncState.conflict);
      expect(
        retained?.conflictPolicy,
        LifeMateMutationConflictPolicy.explicitVersionResolution,
      );
      expect(retained?.expectedRevision, '7');
      expect(
        LifeMateConflictPolicy.resolve(
          const LifeMateConflictContext(
            domain: LifeMateConflictDomain.treatment,
            expectedRevision: '7',
            serverRevision: '8',
          ),
        ),
        LifeMateConflictDisposition.explicitResolutionRequired,
      );
    },
  );

  test('503 retains mutation with bounded server retry state', () async {
    final database = sqlite3.openInMemory();
    final now = DateTime.utc(2026, 9, 5, 3);
    final store = LifeMateLocalHealthStore.forTesting(
      database: database,
      keyBytes: key,
      now: () => now,
    );
    addTearDown(store.close);
    final outbox = LifeMateLocalMutationOutbox(store: store, now: () => now);
    await outbox.enqueue(
      namespace: namespace,
      mutation: treatmentMutation('server-retry'),
    );

    final result = await LifeMateLocalMutationReplayEngine(
      outbox: outbox,
      transport: const _StatusTransport(503),
      now: () => now,
    ).replayEligible(namespace: namespace);

    expect(result.confirmed, 0);
    expect(result.retainedForRetry, 1);
    expect(result.remaining, 1);
    final retained = await outbox.get(
      namespace: namespace,
      mutationId: 'server-retry',
    );
    expect(retained?.state, LifeMateMutationSyncState.retryScheduled);
    expect(retained?.errorClass, LifeMateMutationErrorClass.server);
    expect(retained?.nextAttemptAtUtc, now.add(const Duration(seconds: 15)));
    expect(await outbox.eligible(namespace: namespace, atUtc: now), isEmpty);
  });
}

final class _StatusTransport implements LifeMateMutationReplayTransport {
  const _StatusTransport(this.statusCode);

  final int statusCode;

  @override
  Future<LifeMateMutationReplayResponse> send(
    LifeMateDurableMutation mutation,
  ) async {
    return LifeMateMutationReplayResponse(statusCode);
  }
}
