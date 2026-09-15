import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:lifemate_core/lifemate_core.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('offline symptom enqueue requires the approved catalog snapshot', () async {
    final store = LifeMateLocalHealthStore.forTesting(
      database: sqlite3.openInMemory(),
      keyBytes: Uint8List.fromList(List<int>.generate(32, (index) => index + 1)),
    );
    addTearDown(store.close);

    final identityStore = LifeMateOfflineIdentityAdoptionStore.forTesting(
      _MemoryIdentityStorage(),
    );
    await identityStore.remember(
      environmentId: 'https://api.example.test',
      legacyAccountId: 'legacy-auth-a',
      accountId: 'account-a',
      personId: 'person-a',
    );

    final coordinator = CocoonPregnancyOfflineOwnerCoordinator(
      apiBaseUri: Uri.parse('https://api.example.test'),
      legacyAccountId: 'legacy-auth-a',
      accessToken: () => 'token',
      identityResolver: () async => const LifeMateCapabilitySnapshot(
        accountId: 'account-a',
        selfPersonId: 'person-a',
        applications: <String>{'cocoonmate'},
        features: <String>{},
      ),
      identityStore: identityStore,
      localStore: store,
    );

    final catalog = CocoonApprovedSymptomCatalog(
      version: 'pregnancy-symptoms-v1',
      codes: const <String>['nausea'],
    );
    const requestId = '123e4567-e89b-42d3-a456-426614174321';

    await expectLater(
      coordinator.enqueueSymptom(
        clientRequestId: requestId,
        observedAtUtc: DateTime.utc(2026, 9, 15, 5),
        localDate: DateTime(2026, 9, 15),
        symptomCode: 'invented-code',
        intensity: 'mild',
        approvedCatalog: catalog,
      ),
      throwsArgumentError,
    );
    expect(await coordinator.pendingPregnancyMutationIds(), isEmpty);

    await coordinator.enqueueSymptom(
      clientRequestId: requestId,
      observedAtUtc: DateTime.utc(2026, 9, 15, 5),
      localDate: DateTime(2026, 9, 15),
      symptomCode: 'nausea',
      intensity: 'mild',
      approvedCatalog: catalog,
    );
    expect(await coordinator.pendingPregnancyMutationIds(), <String>{requestId});
  });
}

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
