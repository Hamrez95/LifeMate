import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:lifemate_core/lifemate_core.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  final key = Uint8List.fromList(List<int>.generate(32, (index) => index + 1));
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
    'shared runtime caches Women Health snapshot in owner namespace only',
    () async {
      final store = LifeMateLocalHealthStore.forTesting(
        database: sqlite3.openInMemory(),
        keyBytes: key,
      );
      final ownerRuntime = await _openRuntime(store, owner);
      final otherRuntime = await _openRuntime(store, otherPerson);
      addTearDown(() {
        ownerRuntime.close();
        otherRuntime.close();
        store.close();
      });

      await ownerRuntime.cacheWomenCalendarSnapshot(
        profile: const <String, dynamic>{
          'algorithmVersion':
              WomenCalendarOfflineEngine.canonicalAlgorithmVersion,
          'lastPeriodStart': '2026-08-20',
          'cycleLength': 28,
          'periodLength': 5,
        },
        episodes: const <Map<String, dynamic>>[
          <String, dynamic>{'startedOn': '2026-08-20', 'endedOn': '2026-08-24'},
        ],
        lifecycleState: WomenHealthLifecycleState.active,
      );

      final cached = await ownerRuntime.readWomenCalendarSnapshot();
      expect(cached, isNotNull);
      expect(cached!.lifecycleState, WomenHealthLifecycleState.active);
      expect(cached.profile['cycleLength'], 28);
      expect(await otherRuntime.readWomenCalendarSnapshot(), isNull);
    },
  );

  test(
    'shared runtime projects pending owner daily log without confirming it',
    () async {
      final store = LifeMateLocalHealthStore.forTesting(
        database: sqlite3.openInMemory(),
        keyBytes: key,
      );
      final runtime = await _openRuntime(store, owner);
      addTearDown(() {
        runtime.close();
        store.close();
      });

      await runtime.enqueueWomenDailyLogUpsert(
        mutationId: 'women-log-runtime-0001',
        loggedOn: DateTime(2026, 9, 5),
        version: 3,
        mood: 'good',
        energyLevel: 4,
        periodFlow: 'medium',
        painLevel: 2,
        symptoms: const <String>{'cramps'},
        privateNotes: 'owner only',
        createdAtUtc: DateTime.utc(2026, 9, 5, 19),
      );

      final projected = await runtime.projectWomenDailyLogs(
        serverRows: const <Map<String, dynamic>>[
          <String, dynamic>{
            'loggedOn': '2026-09-05',
            'version': 3,
            'periodFlow': 'light',
            'painLevel': 1,
          },
        ],
        fromDate: DateTime(2026, 9, 5),
        toDate: DateTime(2026, 9, 5),
      );

      expect(projected.rows, hasLength(1));
      expect(projected.rows.single['periodFlow'], 'medium');
      expect(projected.rows.single['pendingSync'], isTrue);
      expect(projected.rows.single['serverConfirmed'], isFalse);
      expect(projected.pendingDates, contains('2026-09-05'));
      expect(projected.conflictDates, isEmpty);

      final stored = await LifeMateLocalMutationOutbox(
        store: store,
      ).get(namespace: owner, mutationId: 'women-log-runtime-0001');
      expect(stored?.domain, LifeMateMutationDomain.womenHealth);
      expect(stored?.endpointPath, '/api/v1/women-calendar/daily-logs');
      expect(stored?.payload['mood'], 'good');
      expect(stored?.payload['energyLevel'], 4);
      expect(stored?.payload['privateNotes'], 'owner only');
      expect(stored?.payload.containsKey('shareSummaryWithCompanion'), isFalse);
    },
  );

  test(
    'shared runtime pending Women Health mutation cannot cross Person namespace',
    () async {
      final store = LifeMateLocalHealthStore.forTesting(
        database: sqlite3.openInMemory(),
        keyBytes: key,
      );
      final ownerRuntime = await _openRuntime(store, owner);
      final otherRuntime = await _openRuntime(store, otherPerson);
      addTearDown(() {
        ownerRuntime.close();
        otherRuntime.close();
        store.close();
      });

      await ownerRuntime.enqueueWomenDailyLogUpsert(
        mutationId: 'women-log-runtime-0002',
        loggedOn: DateTime(2026, 9, 6),
        version: 0,
        symptoms: const <String>{'headache'},
        createdAtUtc: DateTime.utc(2026, 9, 5, 20),
      );

      final otherProjection = await otherRuntime.projectWomenDailyLogs(
        serverRows: const <Map<String, dynamic>>[],
        fromDate: DateTime(2026, 9, 6),
        toDate: DateTime(2026, 9, 6),
      );
      expect(otherProjection.rows, isEmpty);
      expect(otherProjection.pendingDates, isEmpty);
    },
  );

  test('shared runtime preserves explicit pending delete semantics', () async {
    final store = LifeMateLocalHealthStore.forTesting(
      database: sqlite3.openInMemory(),
      keyBytes: key,
    );
    final runtime = await _openRuntime(store, owner);
    addTearDown(() {
      runtime.close();
      store.close();
    });

    await runtime.enqueueWomenDailyLogDelete(
      mutationId: 'women-log-runtime-delete-0001',
      loggedOn: DateTime(2026, 9, 5),
      version: 5,
      createdAtUtc: DateTime.utc(2026, 9, 5, 20, 30),
    );

    final projected = await runtime.projectWomenDailyLogs(
      serverRows: const <Map<String, dynamic>>[
        <String, dynamic>{
          'loggedOn': '2026-09-05',
          'version': 5,
          'periodFlow': 'medium',
        },
      ],
      fromDate: DateTime(2026, 9, 5),
      toDate: DateTime(2026, 9, 5),
    );

    expect(projected.rows, isEmpty);
    expect(projected.pendingDeletedDates, contains('2026-09-05'));
    expect(projected.pendingDates, contains('2026-09-05'));
  });
}

Future<LifeMateSharedOfflineRuntime> _openRuntime(
  LifeMateLocalHealthStore store,
  LifeMateLocalNamespace namespace,
) => LifeMateSharedOfflineRuntime.open(
  namespace: LifeMateOfflineNamespace(
    environmentId: namespace.environmentId,
    accountId: namespace.accountId,
    personId: namespace.personId,
  ),
  timeZone: 'Asia/Tehran',
  apiBaseUri: Uri.parse('https://api.example.test'),
  accessToken: () => 'token',
  store: store,
  legacyStorage: _MemoryStorage(),
);

final class _MemoryStorage implements LifeMateMutationStorage {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<Map<String, String>> readAll() async =>
      Map<String, String>.from(_values);

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }
}
