import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:lifemate_core/lifemate_core.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  final key = List<int>.generate(32, (index) => index + 1);
  final personA = LifeMateLocalNamespace(
    environmentId: 'production',
    accountId: 'account-a',
    personId: 'person-a',
  );
  final personB = LifeMateLocalNamespace(
    environmentId: 'production',
    accountId: 'account-a',
    personId: 'person-b',
  );

  test('persists canonical owner cycle snapshot in protected Person namespace', () async {
    final database = sqlite3.openInMemory();
    final now = DateTime.utc(2026, 9, 5, 18, 45);
    final store = LifeMateLocalHealthStore.forTesting(
      database: database,
      keyBytes: key,
      now: () => now,
    );
    final snapshotStore = WomenCalendarOfflineSnapshotStore(
      store: store,
      namespace: personA,
    );

    await snapshotStore.write(
      profile: _profile(),
      episodes: _episodes(),
      lifecycleState: WomenHealthLifecycleState.active,
    );

    final snapshot = await snapshotStore.read();
    expect(snapshot, isNotNull);
    expect(snapshot!.profile['algorithmVersion'], 'calendar-estimate-v1');
    expect(snapshot.episodes, hasLength(3));
    expect(snapshot.lifecycleState, WomenHealthLifecycleState.active);
    expect(snapshot.storedAtUtc, now);

    final estimate = WomenCalendarOfflineEngine.calculateFromCanonicalSnapshot(
      profile: snapshot.profile,
      episodes: snapshot.episodes,
      today: DateTime(2026, 9, 5),
    );
    expect(estimate.cycleDay, 11);

    store.close();
  });

  test('same account cannot read another Person cycle snapshot', () async {
    final database = sqlite3.openInMemory();
    final store = LifeMateLocalHealthStore.forTesting(
      database: database,
      keyBytes: key,
    );
    await WomenCalendarOfflineSnapshotStore(
      store: store,
      namespace: personA,
    ).write(
      profile: _profile(),
      episodes: _episodes(),
      lifecycleState: WomenHealthLifecycleState.active,
    );

    final otherPerson = WomenCalendarOfflineSnapshotStore(
      store: store,
      namespace: personB,
    );
    expect(await otherPerson.read(), isNull);

    store.close();
  });

  test('algorithm mismatch is rejected before it becomes durable cache', () async {
    final database = sqlite3.openInMemory();
    final store = LifeMateLocalHealthStore.forTesting(
      database: database,
      keyBytes: key,
    );
    final snapshotStore = WomenCalendarOfflineSnapshotStore(
      store: store,
      namespace: personA,
    );
    final invalidProfile = _profile()
      ..['algorithmVersion'] = 'calendar-estimate-v2';

    await expectLater(
      snapshotStore.write(
        profile: invalidProfile,
        episodes: _episodes(),
        lifecycleState: WomenHealthLifecycleState.active,
      ),
      throwsA(isA<WomenCalendarAlgorithmVersionMismatchException>()),
    );
    expect(await snapshotStore.read(), isNull);

    store.close();
  });

  test('pregnancy lifecycle remains explicit in durable owner snapshot', () async {
    final database = sqlite3.openInMemory();
    final store = LifeMateLocalHealthStore.forTesting(
      database: database,
      keyBytes: key,
    );
    final snapshotStore = WomenCalendarOfflineSnapshotStore(
      store: store,
      namespace: personA,
    );

    await snapshotStore.write(
      profile: _profile(),
      episodes: _episodes(),
      lifecycleState: WomenHealthLifecycleState.pausedForPregnancy,
    );
    final snapshot = await snapshotStore.read();

    expect(snapshot!.lifecycleState, WomenHealthLifecycleState.pausedForPregnancy);
    expect(
      WomenCalendarOfflineEngine.shouldSchedulePersonalCycleReminders(
        womenHealthEnabled: true,
        remindersEnabled: true,
        lifecycleState: snapshot.lifecycleState,
      ),
      isFalse,
    );

    store.close();
  });
}

Map<String, dynamic> _profile() => <String, dynamic>{
  'algorithmVersion': 'calendar-estimate-v1',
  'lastPeriodStart': '2026-08-26',
  'cycleLength': 28,
  'periodLength': 5,
};

List<Map<String, dynamic>> _episodes() => <Map<String, dynamic>>[
  <String, dynamic>{'startedOn': '2026-07-01'},
  <String, dynamic>{'startedOn': '2026-07-29'},
  <String, dynamic>{'startedOn': '2026-08-26'},
];
