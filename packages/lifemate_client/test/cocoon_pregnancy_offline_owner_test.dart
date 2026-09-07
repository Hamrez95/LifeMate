import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:lifemate_core/lifemate_core.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  final key = Uint8List.fromList(
    List<int>.generate(32, (index) => index + 1),
  );

  test(
    'authoritative bootstrap survives coordinator recreation as owner snapshot',
    () async {
      final localStore = LifeMateLocalHealthStore.forTesting(
        database: sqlite3.openInMemory(),
        keyBytes: key,
      );
      final identityStorage = _MemoryIdentityStorage();
      final legacyStorage = _MemoryMutationStorage();
      addTearDown(localStore.close);

      final first = _coordinator(
        localStore: localStore,
        identityStorage: identityStorage,
        legacyStorage: legacyStorage,
      );
      await first.cacheAuthoritativeBootstrap(_bootstrap());

      final reopened = _coordinator(
        localStore: localStore,
        identityStorage: identityStorage,
        legacyStorage: legacyStorage,
      );
      final cached = await reopened.readCachedOwnerSnapshot();

      expect(cached, isNotNull);
      expect(cached!.contractVersion, 1);
      expect(cached.episode, isNotNull);
      expect(cached.episode!.id, 'episode-a');
      expect(cached.episode!.motherPersonId, 'person-a');
      expect(cached.episode!.status, CocoonPregnancyEpisodeStatus.active);
      expect(cached.episode!.version, 4);
      expect(cached.episode!.dating.lmpDate, '2026-07-01');
      expect(cached.episode!.dating.gestationalAge, isNull);
    },
  );

  test('bootstrap Person mismatch fails before adopting local owner identity', () async {
    final localStore = LifeMateLocalHealthStore.forTesting(
      database: sqlite3.openInMemory(),
      keyBytes: key,
    );
    final identityStorage = _MemoryIdentityStorage();
    final identityStore = LifeMateOfflineIdentityAdoptionStore.forTesting(
      identityStorage,
    );
    addTearDown(localStore.close);

    final coordinator = CocoonPregnancyOfflineOwnerCoordinator(
      apiBaseUri: Uri.parse('https://api.example.test'),
      legacyAccountId: 'legacy-auth-a',
      accessToken: () => 'token',
      identityResolver: () async => const LifeMateCapabilitySnapshot(
        accountId: 'account-a',
        selfPersonId: 'person-other',
        applications: <String>{},
        features: <String>{},
      ),
      identityStore: identityStore,
      localStore: localStore,
      legacyStorage: _MemoryMutationStorage(),
    );

    await expectLater(
      coordinator.cacheAuthoritativeBootstrap(_bootstrap()),
      throwsA(isA<CocoonOfflineOwnerIdentityMismatchException>()),
    );
    expect(
      await identityStore.lookup(
        environmentId: 'https://api.example.test',
        legacyAccountId: 'legacy-auth-a',
      ),
      isNull,
    );
  });

  test('server cache opt-out revokes restart lookup without deleting by guess', () async {
    final localStore = LifeMateLocalHealthStore.forTesting(
      database: sqlite3.openInMemory(),
      keyBytes: key,
    );
    final identityStorage = _MemoryIdentityStorage();
    final legacyStorage = _MemoryMutationStorage();
    addTearDown(localStore.close);

    final coordinator = _coordinator(
      localStore: localStore,
      identityStorage: identityStorage,
      legacyStorage: legacyStorage,
    );
    await coordinator.cacheAuthoritativeBootstrap(_bootstrap());
    expect(await coordinator.readCachedOwnerSnapshot(), isNotNull);

    await coordinator.cacheAuthoritativeBootstrap(
      _bootstrap(cachedOwnerSnapshotAllowed: false),
    );

    expect(await coordinator.readCachedOwnerSnapshot(), isNull);
  });
}

CocoonPregnancyOfflineOwnerCoordinator _coordinator({
  required LifeMateLocalHealthStore localStore,
  required _MemoryIdentityStorage identityStorage,
  required _MemoryMutationStorage legacyStorage,
}) => CocoonPregnancyOfflineOwnerCoordinator(
  apiBaseUri: Uri.parse('https://api.example.test'),
  legacyAccountId: 'legacy-auth-a',
  accessToken: () => 'token',
  identityResolver: () async => const LifeMateCapabilitySnapshot(
    accountId: 'account-a',
    selfPersonId: 'person-a',
    applications: <String>{'cocoonmate'},
    features: <String>{},
  ),
  identityStore: LifeMateOfflineIdentityAdoptionStore.forTesting(identityStorage),
  localStore: localStore,
  legacyStorage: legacyStorage,
);

CocoonBootstrapSnapshot _bootstrap({bool cachedOwnerSnapshotAllowed = true}) =>
    CocoonBootstrapSnapshot.fromJson(<String, dynamic>{
      'contractVersion': 1,
      'subject': <String, dynamic>{'personId': 'person-a'},
      'enrollmentState': 'active',
      'entitlementState': <String, dynamic>{'state': 'active'},
      'applicationState': <String, dynamic>{
        'availability': 'available',
        'enrollmentState': 'active',
      },
      'commerceEligibility': <String, dynamic>{
        'state': 'entitled',
        'offerAvailable': false,
        'conversionEligible': false,
      },
      'activeEpisode': <String, dynamic>{
        'id': 'episode-a',
        'motherPersonId': 'person-a',
        'status': 'active',
        'dating': <String, dynamic>{
          'method': 'lmp',
          'lmpDate': '2026-07-01',
          'estimatedDueDate': '2027-04-07',
          'gestationalAge': <String, dynamic>{
            'totalDays': 68,
            'week': 9,
            'day': 5,
            'basis': 'lmp',
          },
        },
        'version': 4,
        'updatedAtUtc': '2026-09-06T20:00:00Z',
      },
      'runtime': <String, dynamic>{
        'serverAuthoritativeSharing': true,
        'serverAuthoritativeEntitlementActivation': true,
        'cachedOwnerSnapshotAllowed': cachedOwnerSnapshotAllowed,
        'cachedSharedSnapshotAllowed': false,
      },
    });

final class _MemoryIdentityStorage implements LifeMateOfflineIdentityStorage {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }
}

final class _MemoryMutationStorage implements LifeMateMutationStorage {
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
