import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:lifemate_core/lifemate_core.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  const legacyAccountId = 'legacy-auth-account';
  final key = Uint8List.fromList(List<int>.generate(32, (index) => index + 1));
  final namespace = LifeMateLocalNamespace(
    environmentId: 'production',
    accountId: 'canonical-account',
    personId: 'person-a',
  );

  test('durable client enqueues validated treatment edit in adopted namespace', () async {
    final store = LifeMateLocalHealthStore.forTesting(
      database: sqlite3.openInMemory(),
      keyBytes: key,
    );
    final api = DurableLifeMateApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'token',
      accountId: () => legacyAccountId,
    );
    await api.adoptSharedOfflineRuntime(
      environmentId: namespace.environmentId,
      accountId: namespace.accountId,
      personId: namespace.personId,
      legacyAuthenticatedAccountId: legacyAccountId,
      timeZone: 'Asia/Tehran',
      localStore: store,
      legacyStorage: _MemoryStorage(),
    );

    const requestId = 'offline-treatment-edit-1';
    const planId = '123e4567-e89b-42d3-a456-426614174701';
    final mutation = await api.enqueueOfflineTreatmentPlanEdit(
      clientRequestId: requestId,
      treatmentPlanId: planId,
      version: 7,
      medicationVersion: 4,
      medicationName: 'Medication A',
      strengthText: '500 mg',
      form: 'tablet',
      doseText: '1 tablet',
      instructions: 'As prescribed',
      startDate: DateTime(2026, 9, 1),
      endDate: DateTime(2026, 9, 30),
      timeZone: 'Asia/Tehran',
      schedules: const <Map<String, String>>[
        <String, String>{'dayOfWeek': 'monday', 'localTime': '08:00'},
        <String, String>{'dayOfWeek': 'monday', 'localTime': '16:00'},
      ],
      patientReminderMinutesBefore: 15,
      caregiverReminderMinutesBefore: 30,
      status: 'active',
    );

    expect(mutation.mutationId, requestId);
    expect(mutation.endpointPath, '/api/v1/treatment-plans/$planId');
    expect(mutation.expectedRevision, '7');
    expect(mutation.payload['schedules'], <Map<String, String>>[
      <String, String>{'dayOfWeek': 'monday', 'localTime': '08:00'},
      <String, String>{'dayOfWeek': 'monday', 'localTime': '16:00'},
    ]);
    expect(await api.pendingMutationCount(), 1);

    final stored = await LifeMateLocalMutationOutbox(store: store).get(
      namespace: namespace,
      mutationId: requestId,
    );
    expect(stored?.domain, LifeMateMutationDomain.treatment);
    expect(stored?.sourceKey, planId);
    expect(stored?.state, LifeMateMutationSyncState.pending);

    api.close();
    store.close();
  });

  test('treatment enqueue fails before canonical runtime adoption', () async {
    final api = DurableLifeMateApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'token',
      accountId: () => legacyAccountId,
    );

    await expectLater(
      api.enqueueOfflineTreatmentPlanEdit(
        clientRequestId: 'offline-treatment-edit-2',
        treatmentPlanId: '123e4567-e89b-42d3-a456-426614174702',
        version: 1,
        medicationVersion: 1,
        medicationName: 'Medication B',
        doseText: '1 tablet',
        startDate: DateTime(2026, 9, 5),
        timeZone: 'Asia/Tehran',
        schedules: const <Map<String, String>>[
          <String, String>{'dayOfWeek': 'tuesday', 'localTime': '09:00'},
        ],
        patientReminderMinutesBefore: 0,
        caregiverReminderMinutesBefore: 0,
        status: 'active',
      ),
      throwsStateError,
    );

    api.close();
  });
}

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
