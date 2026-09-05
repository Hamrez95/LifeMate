import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_core/lifemate_core.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('403 is terminal rejected instead of an auth retry loop', () async {
    final database = sqlite3.openInMemory();
    final store = LifeMateLocalHealthStore.forTesting(
      database: database,
      keyBytes: List<int>.generate(32, (index) => index + 1),
    );
    final namespace = LifeMateLocalNamespace(
      environmentId: 'test',
      accountId: 'account',
      personId: 'person',
    );
    final outbox = LifeMateLocalMutationOutbox(store: store);
    await outbox.enqueue(
      namespace: namespace,
      mutation: LifeMateDurableMutation(
        mutationId: 'forbidden-action',
        domain: LifeMateMutationDomain.sharedAuthorization,
        sourceKey: 'grant-revoked',
        method: 'POST',
        endpointPath: '/api/v1/shared-access/action',
        payload: const <String, dynamic>{'clientRequestId': 'forbidden-action'},
        createdAtUtc: DateTime.utc(2026, 9, 5, 2),
        timeZone: 'Asia/Tehran',
      ),
    );

    final result = await LifeMateLocalMutationReplayEngine(
      outbox: outbox,
      transport: const _ForbiddenTransport(),
    ).replayEligible(namespace: namespace);

    expect(result.rejected, 1);
    expect(result.retainedForRetry, 0);
    expect(result.remaining, 0);
    final retained = await outbox.get(
      namespace: namespace,
      mutationId: 'forbidden-action',
    );
    expect(retained?.state, LifeMateMutationSyncState.rejected);
    expect(retained?.errorClass, LifeMateMutationErrorClass.clientRejected);
    store.close();
  });
}

final class _ForbiddenTransport implements LifeMateMutationReplayTransport {
  const _ForbiddenTransport();

  @override
  Future<LifeMateMutationReplayResponse> send(
    LifeMateDurableMutation mutation,
  ) async => const LifeMateMutationReplayResponse(403);
}
