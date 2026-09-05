import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_core/lifemate_core.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  LifeMateLocalHealthStore openStore() => LifeMateLocalHealthStore.forTesting(
    database: sqlite3.openInMemory(),
    keyBytes: List<int>.generate(32, (index) => index + 1),
    now: () => DateTime.utc(2026, 9, 5, 1, 0),
  );

  test('checkpoint round-trips server cursor and revision in protected store', () async {
    final store = openStore();
    final checkpoints = LifeMateLocalSyncCheckpointStore(store);
    final namespace = LifeMateLocalNamespace(
      environmentId: 'production',
      accountId: 'account-a',
      personId: 'person-a',
    );

    await checkpoints.write(
      namespace: namespace,
      domain: LifeMateLocalProjectionDomain.treatmentOccurrence,
      cursor: 'server-cursor-42',
      serverUpdatedAtUtc: DateTime.utc(2026, 9, 5, 0, 55),
      sourceRevision: 'snapshot-v9',
    );

    final value = await checkpoints.read(
      namespace: namespace,
      domain: LifeMateLocalProjectionDomain.treatmentOccurrence,
    );
    expect(value, isNotNull);
    expect(value!.cursor, 'server-cursor-42');
    expect(value.sourceRevision, 'snapshot-v9');
    expect(value.serverUpdatedAtUtc, DateTime.utc(2026, 9, 5, 0, 55));
    expect(value.storedAtUtc, DateTime.utc(2026, 9, 5, 1));

    store.close();
  });

  test('same domain checkpoint is isolated by Account and Person', () async {
    final store = openStore();
    final checkpoints = LifeMateLocalSyncCheckpointStore(store);
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
    final otherAccount = LifeMateLocalNamespace(
      environmentId: 'production',
      accountId: 'account-b',
      personId: 'person-a',
    );

    await checkpoints.write(
      namespace: owner,
      domain: LifeMateLocalProjectionDomain.pregnancySnapshot,
      cursor: 'owner-only',
    );

    expect(
      (await checkpoints.read(
        namespace: owner,
        domain: LifeMateLocalProjectionDomain.pregnancySnapshot,
      ))?.cursor,
      'owner-only',
    );
    expect(
      await checkpoints.read(
        namespace: otherPerson,
        domain: LifeMateLocalProjectionDomain.pregnancySnapshot,
      ),
      isNull,
    );
    expect(
      await checkpoints.read(
        namespace: otherAccount,
        domain: LifeMateLocalProjectionDomain.pregnancySnapshot,
      ),
      isNull,
    );

    store.close();
  });

  test('checkpoint clear does not delete server projection records', () async {
    final store = openStore();
    final checkpoints = LifeMateLocalSyncCheckpointStore(store);
    final namespace = LifeMateLocalNamespace(
      environmentId: 'production',
      accountId: 'account-a',
      personId: 'person-a',
    );
    await store.putProjection(
      namespace: namespace,
      domain: LifeMateLocalProjectionDomain.careEvent,
      recordKey: 'event-1',
      payload: const <String, dynamic>{'status': 'scheduled'},
    );
    await checkpoints.write(
      namespace: namespace,
      domain: LifeMateLocalProjectionDomain.careEvent,
      cursor: 'cursor-1',
    );

    await checkpoints.clear(
      namespace: namespace,
      domain: LifeMateLocalProjectionDomain.careEvent,
    );

    expect(
      await checkpoints.read(
        namespace: namespace,
        domain: LifeMateLocalProjectionDomain.careEvent,
      ),
      isNull,
    );
    expect(
      await store.readProjection(
        namespace: namespace,
        domain: LifeMateLocalProjectionDomain.careEvent,
        recordKey: 'event-1',
      ),
      isNotNull,
    );
    store.close();
  });

  test('local-only domains cannot receive server sync checkpoints', () async {
    final store = openStore();
    final checkpoints = LifeMateLocalSyncCheckpointStore(store);
    final namespace = LifeMateLocalNamespace(
      environmentId: 'production',
      accountId: 'account-a',
      personId: 'person-a',
    );

    for (final domain in <LifeMateLocalProjectionDomain>[
      LifeMateLocalProjectionDomain.syncMetadata,
      LifeMateLocalProjectionDomain.pendingMutation,
      LifeMateLocalProjectionDomain.notificationSchedule,
    ]) {
      await expectLater(
        checkpoints.write(
          namespace: namespace,
          domain: domain,
          cursor: 'cursor',
        ),
        throwsArgumentError,
      );
    }
    store.close();
  });
}
