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

  test(
    'validated daily log is durably queued only in owner Person namespace',
    () async {
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
      expect(
        queued.conflictPolicy,
        LifeMateMutationConflictPolicy.deduplicateAndMerge,
      );
      expect(
        await outbox.get(
          namespace: otherPerson,
          mutationId: 'women-log-owner-0001',
        ),
        isNull,
      );
    },
  );

  test(
    'private owner check-in carries mood and energy but never sharing state',
    () {
      final mutation = LifeMateOfflineWomenDailyLogMutation.buildUpsert(
        mutationId: 'women-owner-checkin-0001',
        loggedOn: DateTime(2026, 9, 6),
        version: 3,
        timeZone: 'Asia/Tehran',
        mood: 'GOOD',
        energyLevel: 4,
        painLevel: 1,
        symptoms: const <String>{'fatigue'},
        privateNotes: 'owner only',
        createdAtUtc: DateTime.utc(2026, 9, 6, 2),
      );

      expect(mutation.payload['mood'], 'good');
      expect(mutation.payload['energyLevel'], 4);
      expect(mutation.payload['painLevel'], 1);
      expect(mutation.payload['symptoms'], <String>['fatigue']);
      expect(mutation.payload['privateNotes'], 'owner only');
      expect(
        mutation.payload.containsKey('shareSummaryWithCompanion'),
        isFalse,
      );
    },
  );

  test(
    'invalid owner check-in fields fail before durable persistence',
    () async {
      final store = LifeMateLocalHealthStore.forTesting(
        database: sqlite3.openInMemory(),
        keyBytes: key,
      );
      addTearDown(store.close);
      final outbox = LifeMateLocalMutationOutbox(store: store);

      for (final values in <({String mood, int energy})>[
        (mood: 'unsupported', energy: 3),
        (mood: 'good', energy: 0),
        (mood: 'good', energy: 6),
      ]) {
        await expectLater(
          () => LifeMateOfflineWomenDailyLogMutation.enqueueUpsert(
            outbox: outbox,
            namespace: owner,
            mutationId: 'women-log-invalid-${values.mood}-${values.energy}',
            loggedOn: DateTime(2026, 9, 6),
            version: 0,
            timeZone: 'Asia/Tehran',
            mood: values.mood,
            energyLevel: values.energy,
          ),
          throwsArgumentError,
        );
      }
      expect(await outbox.list(namespace: owner), isEmpty);
    },
  );

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
