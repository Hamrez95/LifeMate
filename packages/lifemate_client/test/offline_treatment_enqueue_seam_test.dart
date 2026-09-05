import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lifemate_client/lifemate_client.dart';
import 'package:lifemate_core/lifemate_core.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  final key = List<int>.generate(32, (index) => index + 1);
  final namespace = LifeMateLocalNamespace(
    environmentId: 'production',
    accountId: 'account-a',
    personId: 'person-a',
  );

  test('runtime queues treatment edit only inside active Person namespace', () async {
    final database = sqlite3.openInMemory();
    final store = LifeMateLocalHealthStore.forTesting(
      database: database,
      keyBytes: key,
    );
    final runtime = await LifeMateSharedOfflineRuntime.open(
      namespace: namespace,
      timeZone: 'Europe/Berlin',
      apiBaseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'fresh-token',
      store: store,
      legacyStorage: _MemoryStorage(),
      httpClient: _NoNetworkClient(),
    );

    final mutation = await runtime.enqueueTreatmentEdit(
      mutationId: '123e4567-e89b-42d3-a456-426614174980',
      treatmentPlanId: '11111111-1111-4111-8111-111111111111',
      version: 7,
      medicationVersion: 3,
      medicationName: 'Medication',
      strengthText: '10 mg',
      form: 'tablet',
      doseText: '1 tablet',
      instructions: 'with food',
      startDate: DateTime(2026, 9, 5),
      endDate: DateTime(2026, 9, 20),
      timeZone: 'Europe/Berlin',
      schedules: const <Map<String, String>>[
        {'dayOfWeek': 'monday', 'localTime': '08:30'},
      ],
      patientReminderMinutesBefore: 30,
      caregiverReminderMinutesBefore: 60,
      status: 'active',
    );

    expect(mutation.domain, LifeMateMutationDomain.treatment);
    expect(
      mutation.conflictPolicy,
      LifeMateMutationConflictPolicy.explicitVersionResolution,
    );
    final outbox = LifeMateLocalMutationOutbox(store: store);
    final ownerMutations = await outbox.list(namespace: namespace);
    expect(ownerMutations, hasLength(1));
    expect(ownerMutations.single.mutationId, mutation.mutationId);
    expect(ownerMutations.single.expectedRevision, '7');

    final otherPerson = LifeMateLocalNamespace(
      environmentId: 'production',
      accountId: 'account-a',
      personId: 'person-b',
    );
    expect(await outbox.list(namespace: otherPerson), isEmpty);

    runtime.close();
    await expectLater(
      runtime.enqueueTreatmentEdit(
        mutationId: '123e4567-e89b-42d3-a456-426614174981',
        treatmentPlanId: '11111111-1111-4111-8111-111111111111',
        version: 7,
        medicationVersion: 3,
        medicationName: 'Medication',
        doseText: '1 tablet',
        startDate: DateTime(2026, 9, 5),
        timeZone: 'Europe/Berlin',
        schedules: const <Map<String, String>>[
          {'dayOfWeek': 'monday', 'localTime': '08:30'},
        ],
        patientReminderMinutesBefore: 30,
        caregiverReminderMinutesBefore: 60,
        status: 'active',
      ),
      throwsStateError,
    );
    store.close();
  });

  test('durable client refuses treatment queue before canonical runtime adoption', () async {
    final client = DurableLifeMateApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'token',
      accountId: () => 'legacy-auth-a',
      innerHttpClient: _NoNetworkClient(),
    );

    await expectLater(
      client.queueTreatmentEdit(
        mutationId: '123e4567-e89b-42d3-a456-426614174982',
        treatmentPlanId: '11111111-1111-4111-8111-111111111111',
        version: 2,
        medicationVersion: 1,
        medicationName: 'Medication',
        doseText: '1 tablet',
        startDate: DateTime(2026, 9, 5),
        timeZone: 'Europe/Berlin',
        schedules: const <Map<String, String>>[
          {'dayOfWeek': 'tuesday', 'localTime': '07:45'},
        ],
        patientReminderMinutesBefore: 30,
        caregiverReminderMinutesBefore: 60,
        status: 'active',
      ),
      throwsStateError,
    );
    client.close();
  });

  test('durable client queues treatment edit through adopted Person runtime', () async {
    final database = sqlite3.openInMemory();
    final store = LifeMateLocalHealthStore.forTesting(
      database: database,
      keyBytes: key,
    );
    final legacyStorage = _MemoryStorage();
    final client = DurableLifeMateApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'token',
      accountId: () => 'legacy-auth-a',
      queue: LifeMateOfflineMutationQueue(storage: legacyStorage),
      innerHttpClient: _NoNetworkClient(),
    );

    await client.adoptSharedOfflineRuntime(
      environmentId: 'production',
      accountId: 'account-a',
      personId: 'person-a',
      legacyAuthenticatedAccountId: 'legacy-auth-a',
      timeZone: 'Europe/Berlin',
      localStore: store,
      legacyStorage: legacyStorage,
    );

    final mutation = await client.queueTreatmentEdit(
      mutationId: '123e4567-e89b-42d3-a456-426614174983',
      treatmentPlanId: '11111111-1111-4111-8111-111111111111',
      version: 4,
      medicationVersion: 2,
      medicationName: 'Medication',
      doseText: '1 tablet',
      startDate: DateTime(2026, 9, 5),
      timeZone: 'Europe/Berlin',
      schedules: const <Map<String, String>>[
        {'dayOfWeek': 'wednesday', 'localTime': '09:15'},
      ],
      patientReminderMinutesBefore: 15,
      caregiverReminderMinutesBefore: 30,
      status: 'active',
    );

    final outbox = LifeMateLocalMutationOutbox(store: store);
    final queued = await outbox.list(namespace: namespace);
    expect(queued, hasLength(1));
    expect(queued.single.mutationId, mutation.mutationId);
    expect(queued.single.expectedRevision, '4');
    expect(queued.single.payload['schedules'], const <Map<String, String>>[
      {'dayOfWeek': 'wednesday', 'localTime': '09:15'},
    ]);

    client.close();
    store.close();
  });
}

final class _MemoryStorage implements LifeMateMutationStorage {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<Map<String, String>> readAll() async =>
      Map<String, String>.from(values);

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

final class _NoNetworkClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    throw StateError('Network must not be used by this test.');
  }
}
