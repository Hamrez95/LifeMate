import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_core/lifemate_core.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  LifeMateLocalHealthStore openStore() => LifeMateLocalHealthStore.forTesting(
    database: sqlite3.openInMemory(),
    keyBytes: List<int>.generate(32, (index) => index + 1),
    now: () => DateTime.utc(2026, 9, 5, 1, 0),
  );

  LifeMateLocalNamespace namespace() => LifeMateLocalNamespace(
    environmentId: 'production',
    accountId: 'account-a',
    personId: 'person-a',
  );

  test('applies upserts and tombstones then advances cursor last', () async {
    final store = openStore();
    final ns = namespace();
    final reconciler = LifeMateLocalProjectionReconciler(store: store);
    await store.putProjection(
      namespace: ns,
      domain: LifeMateLocalProjectionDomain.treatmentOccurrence,
      recordKey: 'old-occurrence',
      payload: const <String, dynamic>{'status': 'scheduled'},
    );

    final result = await reconciler.applyPage(
      namespace: ns,
      domain: LifeMateLocalProjectionDomain.treatmentOccurrence,
      page: LifeMateProjectionPullPage(
        nextCursor: 'cursor-2',
        sourceRevision: 'page-r2',
        serverUpdatedAtUtc: DateTime.utc(2026, 9, 5, 0, 59),
        changes: <LifeMateServerProjectionChange>[
          LifeMateServerProjectionChange.upsert(
            recordKey: 'new-occurrence',
            payload: const <String, dynamic>{'status': 'scheduled'},
            sourceRevision: 'occ-r4',
          ),
          LifeMateServerProjectionChange.delete(recordKey: 'old-occurrence'),
        ],
      ),
    );

    expect(result.applied, 1);
    expect(result.deleted, 1);
    expect(result.affectedRecordKeys, {'new-occurrence', 'old-occurrence'});
    expect(
      await store.readProjection(
        namespace: ns,
        domain: LifeMateLocalProjectionDomain.treatmentOccurrence,
        recordKey: 'old-occurrence',
      ),
      isNull,
    );
    final inserted = await store.readProjection(
      namespace: ns,
      domain: LifeMateLocalProjectionDomain.treatmentOccurrence,
      recordKey: 'new-occurrence',
    );
    expect(inserted?.syncCursor, 'cursor-2');
    expect(inserted?.sourceRevision, 'occ-r4');
    expect(
      (await reconciler.checkpoint(
        namespace: ns,
        domain: LifeMateLocalProjectionDomain.treatmentOccurrence,
      ))?.cursor,
      'cursor-2',
    );
    store.close();
  });

  test('failed page never advances previous checkpoint', () async {
    final store = openStore();
    final ns = namespace();
    final checkpoints = LifeMateLocalSyncCheckpointStore(store);
    final reconciler = LifeMateLocalProjectionReconciler(
      store: store,
      checkpoints: checkpoints,
    );
    await checkpoints.write(
      namespace: ns,
      domain: LifeMateLocalProjectionDomain.careEvent,
      cursor: 'cursor-before',
    );
    final oversized = <String, dynamic>{
      'blob':
          'x' * (LifeMateLocalHealthStore.maximumPlaintextEnvelopeBytes + 32),
    };

    await expectLater(
      reconciler.applyPage(
        namespace: ns,
        domain: LifeMateLocalProjectionDomain.careEvent,
        page: LifeMateProjectionPullPage(
          nextCursor: 'cursor-after',
          changes: <LifeMateServerProjectionChange>[
            LifeMateServerProjectionChange.upsert(
              recordKey: 'event-valid',
              payload: const <String, dynamic>{'status': 'scheduled'},
            ),
            LifeMateServerProjectionChange.upsert(
              recordKey: 'event-too-large',
              payload: oversized,
            ),
          ],
        ),
      ),
      throwsArgumentError,
    );

    expect(
      (await checkpoints.read(
        namespace: ns,
        domain: LifeMateLocalProjectionDomain.careEvent,
      ))?.cursor,
      'cursor-before',
    );
    expect(
      await store.readProjection(
        namespace: ns,
        domain: LifeMateLocalProjectionDomain.careEvent,
        recordKey: 'event-valid',
      ),
      isNotNull,
    );
    store.close();
  });

  test(
    'pre-checkpoint side effect failure keeps old cursor for replay',
    () async {
      final store = openStore();
      final ns = namespace();
      final checkpoints = LifeMateLocalSyncCheckpointStore(store);
      final reconciler = LifeMateLocalProjectionReconciler(
        store: store,
        checkpoints: checkpoints,
      );
      await checkpoints.write(
        namespace: ns,
        domain: LifeMateLocalProjectionDomain.careEvent,
        cursor: 'cursor-before',
      );

      await expectLater(
        reconciler.applyPage(
          namespace: ns,
          domain: LifeMateLocalProjectionDomain.careEvent,
          page: LifeMateProjectionPullPage(
            nextCursor: 'cursor-after',
            changes: <LifeMateServerProjectionChange>[
              LifeMateServerProjectionChange.upsert(
                recordKey: 'event-1',
                payload: const <String, dynamic>{'status': 'scheduled'},
              ),
            ],
          ),
          beforeCheckpoint: (staged) async {
            expect(staged.affectedRecordKeys, {'event-1'});
            expect(
              (await checkpoints.read(
                namespace: ns,
                domain: LifeMateLocalProjectionDomain.careEvent,
              ))?.cursor,
              'cursor-before',
            );
            throw StateError('reminder regeneration failed');
          },
        ),
        throwsStateError,
      );

      expect(
        (await checkpoints.read(
          namespace: ns,
          domain: LifeMateLocalProjectionDomain.careEvent,
        ))?.cursor,
        'cursor-before',
      );
      expect(
        await store.readProjection(
          namespace: ns,
          domain: LifeMateLocalProjectionDomain.careEvent,
          recordKey: 'event-1',
        ),
        isNotNull,
      );
      store.close();
    },
  );

  test(
    'replay of same page is idempotent and keeps local-only mutation',
    () async {
      final store = openStore();
      final ns = namespace();
      final reconciler = LifeMateLocalProjectionReconciler(store: store);
      await store.putProjection(
        namespace: ns,
        domain: LifeMateLocalProjectionDomain.pendingMutation,
        recordKey: 'mutation-1',
        payload: const <String, dynamic>{'state': 'pending'},
      );
      final page = LifeMateProjectionPullPage(
        nextCursor: 'cursor-repeat',
        changes: <LifeMateServerProjectionChange>[
          LifeMateServerProjectionChange.upsert(
            recordKey: 'event-1',
            payload: const <String, dynamic>{'status': 'scheduled'},
          ),
        ],
      );

      await reconciler.applyPage(
        namespace: ns,
        domain: LifeMateLocalProjectionDomain.careEvent,
        page: page,
      );
      await reconciler.applyPage(
        namespace: ns,
        domain: LifeMateLocalProjectionDomain.careEvent,
        page: page,
      );

      expect(
        (await store.listDomain(
          namespace: ns,
          domain: LifeMateLocalProjectionDomain.careEvent,
        )).length,
        1,
      );
      expect(
        await store.readProjection(
          namespace: ns,
          domain: LifeMateLocalProjectionDomain.pendingMutation,
          recordKey: 'mutation-1',
        ),
        isNotNull,
      );
      store.close();
    },
  );

  test('rejects reconciliation into local-only domains', () async {
    final store = openStore();
    final reconciler = LifeMateLocalProjectionReconciler(store: store);
    final page = LifeMateProjectionPullPage(
      nextCursor: 'cursor',
      changes: const <LifeMateServerProjectionChange>[],
    );

    for (final domain in <LifeMateLocalProjectionDomain>[
      LifeMateLocalProjectionDomain.pendingMutation,
      LifeMateLocalProjectionDomain.notificationSchedule,
      LifeMateLocalProjectionDomain.syncMetadata,
    ]) {
      await expectLater(
        reconciler.applyPage(
          namespace: namespace(),
          domain: domain,
          page: page,
        ),
        throwsArgumentError,
      );
    }
    store.close();
  });
}
