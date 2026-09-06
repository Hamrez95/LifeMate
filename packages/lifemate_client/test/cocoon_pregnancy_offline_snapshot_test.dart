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

  test('canonical owner pregnancy snapshot stays Person scoped', () async {
    final store = LifeMateLocalHealthStore.forTesting(
      database: sqlite3.openInMemory(),
      keyBytes: key,
    );
    final ownerRuntime = await _openRuntime(store, owner);
    final otherRuntime = await _openRuntime(store, otherPerson);
    final ownerCache = await CocoonPregnancyOfflineSnapshotCache.open(
      runtime: ownerRuntime,
      store: store,
    );
    final otherCache = await CocoonPregnancyOfflineSnapshotCache.open(
      runtime: otherRuntime,
      store: store,
    );
    addTearDown(() {
      ownerCache.close();
      otherCache.close();
      ownerRuntime.close();
      otherRuntime.close();
      store.close();
    });

    await ownerCache.writeCanonicalOwnerSnapshot(_snapshot('person-a'));

    final cached = await ownerCache.readCanonicalOwnerSnapshot();
    expect(cached?.episode?.id, 'episode-1');
    expect(cached?.episode?.motherPersonId, 'person-a');
    expect(cached?.episode?.dating.lmpDate, '2026-01-01');
    expect(cached?.episode?.dating.gestationalAge, isNull);
    expect(await otherCache.readCanonicalOwnerSnapshot(), isNull);
  });

  test('cache never persists mutable derived gestational week/day', () async {
    final store = LifeMateLocalHealthStore.forTesting(
      database: sqlite3.openInMemory(),
      keyBytes: key,
    );
    final runtime = await _openRuntime(store, owner);
    final cache = await CocoonPregnancyOfflineSnapshotCache.open(
      runtime: runtime,
      store: store,
    );
    addTearDown(() {
      cache.close();
      runtime.close();
      store.close();
    });

    await cache.writeCanonicalOwnerSnapshot(_snapshot('person-a'));
    final record = await store.readProjection(
      namespace: owner,
      domain: LifeMateLocalProjectionDomain.pregnancySnapshot,
      recordKey: 'owner-pregnancy-v1',
    );
    expect(record, isNotNull);
    final episode = record!.payload['episode'] as Map<String, dynamic>;
    final dating = episode['dating'] as Map<String, dynamic>;
    expect(dating.containsKey('gestationalAge'), isFalse);
    expect(dating['lmpDate'], '2026-01-01');
  });

  test('cache rejects a pregnancy episode for another Person', () async {
    final store = LifeMateLocalHealthStore.forTesting(
      database: sqlite3.openInMemory(),
      keyBytes: key,
    );
    final runtime = await _openRuntime(store, owner);
    final cache = await CocoonPregnancyOfflineSnapshotCache.open(
      runtime: runtime,
      store: store,
    );
    addTearDown(() {
      cache.close();
      runtime.close();
      store.close();
    });

    expect(
      () => cache.writeCanonicalOwnerSnapshot(_snapshot('person-b')),
      throwsA(isA<CocoonPregnancyOfflineSnapshotScopeException>()),
    );
    expect(
      await store.readProjection(
        namespace: owner,
        domain: LifeMateLocalProjectionDomain.pregnancySnapshot,
        recordKey: 'owner-pregnancy-v1',
      ),
      isNull,
    );
  });
}

CocoonPregnancySnapshot _snapshot(String motherPersonId) =>
    CocoonPregnancySnapshot(
      contractVersion: 1,
      episode: CocoonPregnancyEpisode(
        id: 'episode-1',
        motherPersonId: motherPersonId,
        status: CocoonPregnancyEpisodeStatus.active,
        dating: const CocoonPregnancyDating(
          method: 'lmp',
          lmpDate: '2026-01-01',
          estimatedDueDate: null,
          referenceDate: null,
          gestationalAgeAtReferenceDays: null,
          gestationalAge: CocoonGestationalAge(
            totalDays: 200,
            week: 28,
            day: 4,
            basis: 'lmp',
          ),
        ),
        outcome: null,
        activatedAtUtc: DateTime.utc(2026, 1, 10),
        endedAtUtc: null,
        version: 3,
        updatedAtUtc: DateTime.utc(2026, 9, 6, 7),
      ),
    );

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
