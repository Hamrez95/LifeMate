import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_core/lifemate_core.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  final key = List<int>.generate(32, (index) => index + 1);
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

  test('validated daily log is durably queued only in owner Person namespace', () async {
    final store = LifeMateLocalHealthStore.forTesting(
      database: sqlite3.openInMemory(),
      keyBytes: key,
    );
    addTearDown(store.close);
    final outbox = LifeMateLocalMutationOutbox(store: store);

    await LifeMateOfflineWomenDailyLogMutation.enqueueUpsert(
      outbox: outbox,
      namespace: owner,
      mutationId: 'women-log-owner-0001',
      loggedOn: DateTime(2026, 9, 5),
      version: 2,
      timeZone: 'Asia/Tehran',
      periodFlow: 'light',
      symptoms: const <String>{'cramps'},
      createdAtUtc: DateTime.utc(2026, 9, 5, 19),
    );

    final queued = await outbox.get(
      namespace: owner,
      mutationId: 'women-log-owner-0001',
    );
    expect(queued, isNotNull);
    expect(queued!.domain, LifeMateMutationDomain.womenHealth);
    expect(queued.conflictPolicy, LifeMateMutationConflictPolicy.deduplicateAndMerge);
    expect(
      await outbox.get(
        namespace: otherPerson,
        mutationId: 'women-log-owner-0001',
      ),
      isNull,
    );
  });

  test('invalid input cannot leave a protected outbox record behind', () async {
    final store = LifeMateLocalHealthStore.forTesting(
      database: sqlite3.openInMemory(),
      keyBytes: key,
    );
    addTearDown(store.close);
    final outbox = LifeMateLocalMutationOutbox(store: store);

    await expectLater(
      () => LifeMateOfflineWomenDailyLogMutation.enqueueUpsert(
        outbox: outbox,
        namespace: owner,
        mutationId: 'women-log-owner-invalid-0001',
        loggedOn: DateTime(2026, 9, 5),
        version: -1,
        timeZone: 'Asia/Tehran',
      ),
      throwsArgumentError,
    );
    expect(await outbox.list(namespace: owner), isEmpty);
  });
}
