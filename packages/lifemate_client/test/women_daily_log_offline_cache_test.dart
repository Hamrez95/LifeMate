import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart'
    hide WomenDailyLogOfflineCache;
import 'package:lifemate_client/src/women_daily_log_offline_cache.dart';
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

  test('confirmed daily-log cache is Person isolated and bounded', () async {
    final store = LifeMateLocalHealthStore.forTesting(
      database: sqlite3.openInMemory(),
      keyBytes: key,
    );
    final ownerCache = WomenDailyLogOfflineCache(
      store: store,
      namespace: owner,
    );
    final otherCache = WomenDailyLogOfflineCache(
      store: store,
      namespace: otherPerson,
    );
    addTearDown(() {
      ownerCache.close();
      otherCache.close();
      store.close();
    });

    await ownerCache.cacheServerDay(
      date: DateTime(2026, 9, 6),
      serverRows: const <Map<String, dynamic>>[
        <String, dynamic>{
          'loggedOn': '2026-09-06',
          'version': 4,
          'mood': 'Good',
          'energyLevel': 4,
          'periodFlow': 'medium',
          'painLevel': 2,
          'symptoms': <String>['cramps'],
          'privateNotes': 'encrypted owner note',
          'shareSummaryWithCompanion': true,
          'unexpectedServerField': 'must-not-be-persisted',
        },
      ],
    );

    final cached = await ownerCache.readServerDay(DateTime(2026, 9, 6));
    expect(cached, hasLength(1));
    expect(cached!.single['version'], 4);
    expect(cached.single['mood'], 'good');
    expect(cached.single['energyLevel'], 4);
    expect(cached.single['privateNotes'], 'encrypted owner note');
    expect(cached.single.containsKey('shareSummaryWithCompanion'), isFalse);
    expect(cached.single.containsKey('unexpectedServerField'), isFalse);
    expect(await otherCache.readServerDay(DateTime(2026, 9, 6)), isNull);
  });

  test('confirmed empty day is distinct from an unsynchronized day', () async {
    final store = LifeMateLocalHealthStore.forTesting(
      database: sqlite3.openInMemory(),
      keyBytes: key,
    );
    final cache = WomenDailyLogOfflineCache(store: store, namespace: owner);
    addTearDown(() {
      cache.close();
      store.close();
    });

    expect(await cache.readServerDay(DateTime(2026, 9, 5)), isNull);

    await cache.cacheServerDay(
      date: DateTime(2026, 9, 5),
      serverRows: const <Map<String, dynamic>>[],
    );

    expect(await cache.readServerDay(DateTime(2026, 9, 5)), isEmpty);
    expect(await cache.readServerDay(DateTime(2026, 9, 4)), isNull);
  });

  test('malformed replacement fails before overwriting confirmed cache', () async {
    final store = LifeMateLocalHealthStore.forTesting(
      database: sqlite3.openInMemory(),
      keyBytes: key,
    );
    final cache = WomenDailyLogOfflineCache(store: store, namespace: owner);
    addTearDown(() {
      cache.close();
      store.close();
    });

    await cache.cacheServerDay(
      date: DateTime(2026, 9, 6),
      serverRows: const <Map<String, dynamic>>[
        <String, dynamic>{
          'loggedOn': '2026-09-06',
          'version': 2,
          'periodFlow': 'light',
        },
      ],
    );

    await expectLater(
      cache.cacheServerDay(
        date: DateTime(2026, 9, 6),
        serverRows: const <Map<String, dynamic>>[
          <String, dynamic>{
            'loggedOn': '2026-09-07',
            'version': 3,
          },
        ],
      ),
      throwsFormatException,
    );

    final cached = await cache.readServerDay(DateTime(2026, 9, 6));
    expect(cached, hasLength(1));
    expect(cached!.single['version'], 2);
    expect(cached.single['periodFlow'], 'light');
  });

  test('confirmed cache rejects malformed companion-only owner fields', () async {
    final store = LifeMateLocalHealthStore.forTesting(
      database: sqlite3.openInMemory(),
      keyBytes: key,
    );
    final cache = WomenDailyLogOfflineCache(store: store, namespace: owner);
    addTearDown(() {
      cache.close();
      store.close();
    });

    await expectLater(
      cache.cacheServerDay(
        date: DateTime(2026, 9, 6),
        serverRows: const <Map<String, dynamic>>[
          <String, dynamic>{
            'loggedOn': '2026-09-06',
            'version': 1,
            'mood': 'unsafe-value',
            'energyLevel': 4,
          },
        ],
      ),
      throwsFormatException,
    );
    await expectLater(
      cache.cacheServerDay(
        date: DateTime(2026, 9, 6),
        serverRows: const <Map<String, dynamic>>[
          <String, dynamic>{
            'loggedOn': '2026-09-06',
            'version': 1,
            'mood': 'good',
            'energyLevel': 6,
          },
        ],
      ),
      throwsFormatException,
    );
    expect(await cache.readServerDay(DateTime(2026, 9, 6)), isNull);
  });

  test('confirmed range preserves empty-day coverage and ordered history', () async {
    final store = LifeMateLocalHealthStore.forTesting(
      database: sqlite3.openInMemory(),
      keyBytes: key,
    );
    final cache = WomenDailyLogOfflineCache(store: store, namespace: owner);
    addTearDown(() {
      cache.close();
      store.close();
    });

    await cache.cacheServerRange(
      fromDate: DateTime(2026, 9, 3),
      toDate: DateTime(2026, 9, 6),
      serverRows: const <Map<String, dynamic>>[
        <String, dynamic>{
          'loggedOn': '2026-09-03',
          'version': 1,
          'periodFlow': 'light',
        },
        <String, dynamic>{
          'loggedOn': '2026-09-06',
          'version': 2,
          'periodFlow': 'heavy',
        },
      ],
    );

    final history = await cache.readServerRange(
      fromDate: DateTime(2026, 9, 3),
      toDate: DateTime(2026, 9, 6),
    );
    expect(history, hasLength(2));
    expect(history!.map((row) => row['loggedOn']), <String>[
      '2026-09-03',
      '2026-09-06',
    ]);
    expect(await cache.readServerDay(DateTime(2026, 9, 4)), isEmpty);
    expect(await cache.readServerDay(DateTime(2026, 9, 5)), isEmpty);
  });

  test('range read fails closed when any day was never confirmed', () async {
    final store = LifeMateLocalHealthStore.forTesting(
      database: sqlite3.openInMemory(),
      keyBytes: key,
    );
    final cache = WomenDailyLogOfflineCache(store: store, namespace: owner);
    addTearDown(() {
      cache.close();
      store.close();
    });

    await cache.cacheServerDay(
      date: DateTime(2026, 9, 3),
      serverRows: const <Map<String, dynamic>>[],
    );
    await cache.cacheServerDay(
      date: DateTime(2026, 9, 5),
      serverRows: const <Map<String, dynamic>>[],
    );

    expect(
      await cache.readServerRange(
        fromDate: DateTime(2026, 9, 3),
        toDate: DateTime(2026, 9, 5),
      ),
      isNull,
    );
  });

  test('range cache rejects duplicate, out-of-window, and oversized input', () async {
    final store = LifeMateLocalHealthStore.forTesting(
      database: sqlite3.openInMemory(),
      keyBytes: key,
    );
    final cache = WomenDailyLogOfflineCache(store: store, namespace: owner);
    addTearDown(() {
      cache.close();
      store.close();
    });

    await expectLater(
      cache.cacheServerRange(
        fromDate: DateTime(2026, 9, 3),
        toDate: DateTime(2026, 9, 4),
        serverRows: const <Map<String, dynamic>>[
          <String, dynamic>{'loggedOn': '2026-09-03', 'version': 1},
          <String, dynamic>{'loggedOn': '2026-09-03', 'version': 2},
        ],
      ),
      throwsFormatException,
    );
    await expectLater(
      cache.cacheServerRange(
        fromDate: DateTime(2026, 9, 3),
        toDate: DateTime(2026, 9, 4),
        serverRows: const <Map<String, dynamic>>[
          <String, dynamic>{'loggedOn': '2026-09-05', 'version': 1},
        ],
      ),
      throwsFormatException,
    );
    await expectLater(
      cache.readServerRange(
        fromDate: DateTime(2026, 1, 1),
        toDate: DateTime(2026, 5, 1),
      ),
      throwsArgumentError,
    );
  });
}
