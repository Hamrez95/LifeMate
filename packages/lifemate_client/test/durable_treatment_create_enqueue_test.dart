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

  test('durable client enqueues bounded treatment create in adopted namespace', () async {
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

    const requestId = 'offline-treatment-create-1';
    const medicationId = '123e4567-e89b-42d3-a456-426614174700';
    await api.enqueueOfflineTreatmentPlanCreate(
      clientRequestId: requestId,
      medicationId: medicationId,
      doseText: '1 tablet',
      instructions: 'As prescribed',
      startDate: DateTime(2026, 9, 5),
      endDate: DateTime(2026, 9, 30),
      timeZone: 'Asia/Tehran',
      schedules: const <Map<String, String>>[
        <String, String>{'dayOfWeek': 'monday', 'localTime': '08:00'},
        <String, String>{'dayOfWeek': 'wednesday', 'localTime': '16:00'},
      ],
      patientReminderMinutesBefore: 15,
      caregiverReminderMinutesBefore: 30,
    );

    expect(await api.pendingMutationCount(), 1);

    final stored = await LifeMateLocalMutationOutbox(store: store).get(
      namespace: namespace,
      mutationId: requestId,
    );
    expect(stored?.mutationId, requestId);
    expect(stored?.method, 'POST');
    expect(stored?.endpointPath, '/api/v1/treatment-plans');
    expect(stored?.expectedRevision, isNull);
    expect(stored?.sourceKey, 'pending-treatment-create:$requestId');
    expect(stored?.domain, LifeMateMutationDomain.treatment);
    expect(stored?.state, LifeMateMutationSyncState.pending);
    expect(stored?.payload['medicationId'], medicationId);
    expect(stored?.payload['schedules'], <Map<String, String>>[
      <String, String>{'dayOfWeek': 'monday', 'localTime': '08:00'},
      <String, String>{'dayOfWeek': 'wednesday', 'localTime': '16:00'},
    ]);
    expect(stored?.payload['recurrence'], <String, dynamic>{
      'version': 2,
      'enabled': false,
    });
    expect(stored?.payload['recurrenceStartLocalTime'], isNull);

    final otherPerson = LifeMateLocalNamespace(
      environmentId: namespace.environmentId,
      accountId: namespace.accountId,
      personId: 'person-b',
    );
    final otherPersonStored = await LifeMateLocalMutationOutbox(store: store).get(
      namespace: otherPerson,
      mutationId: requestId,
    );
    expect(otherPersonStored, isNull);

    api.close();
    store.close();
  });

  test('treatment create enqueue fails before canonical runtime adoption', () {
    final api = DurableLifeMateApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'token',
      accountId: () => legacyAccountId,
    );

    expect(
      () => api.enqueueOfflineTreatmentPlanCreate(
        clientRequestId: 'offline-treatment-create-2',
        medicationId: '123e4567-e89b-42d3-a456-426614174702',
        doseText: '1 tablet',
        startDate: DateTime(2026, 9, 5),
        timeZone: 'Asia/Tehran',
        schedules: const <Map<String, String>>[
          <String, String>{'dayOfWeek': 'tuesday', 'localTime': '09:00'},
        ],
        patientReminderMinutesBefore: 0,
        caregiverReminderMinutesBefore: 0,
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