import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lifemate_client/lifemate_client.dart';
import 'package:lifemate_core/lifemate_core.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('durable client enqueues treatment edit in adopted Person namespace', () async {
    final legacyStorage = _MemoryStorage();
    final queue = LifeMateOfflineMutationQueue(storage: legacyStorage);
    final database = sqlite3.openInMemory();
    final store = LifeMateLocalHealthStore.forTesting(
      database: database,
      keyBytes: List<int>.generate(32, (index) => index + 1),
    );
    final client = DurableLifeMateApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'token',
      accountId: () => 'legacy-auth-a',
      queue: queue,
      innerHttpClient: _StatusClient(200),
    );

    await client.adoptSharedOfflineRuntime(
      environmentId: 'production',
      accountId: 'canonical-account-a',
      personId: 'canonical-person-a',
      legacyAuthenticatedAccountId: 'legacy-auth-a',
      timeZone: 'Asia/Tehran',
      localStore: store,
      legacyStorage: legacyStorage,
    );

    const mutationId = '123e4567-e89b-42d3-a456-426614174970';
    const planId = '123e4567-e89b-42d3-a456-426614174071';
    final acceptedMutationId = await client.enqueueTreatmentPlanEdit(
      mutationId: mutationId,
      treatmentPlanId: planId,
      version: 7,
      medicationVersion: 3,
      medicationName: 'Example',
      doseText: '1 tablet',
      startDate: DateTime(2026, 9, 5),
      timeZone: 'Asia/Tehran',
      schedules: const <Map<String, String>>[
        <String, String>{'dayOfWeek': 'saturday', 'localTime': '08:00'},
      ],
      patientReminderMinutesBefore: 15,
      caregiverReminderMinutesBefore: 30,
      status: 'active',
      localStore: store,
    );

    expect(acceptedMutationId, mutationId);
    expect(await client.pendingMutationCount(), 1);

    final outbox = LifeMateLocalMutationOutbox(store: store);
    final persisted = await outbox.get(
      namespace: LifeMateLocalNamespace(
        environmentId: 'production',
        accountId: 'canonical-account-a',
        personId: 'canonical-person-a',
      ),
      mutationId: mutationId,
    );
    expect(persisted, isNotNull);
    expect(persisted!.domain, LifeMateMutationDomain.treatment);
    expect(persisted.endpointPath, '/api/v1/treatment-plans/$planId');
    expect(persisted.expectedRevision, '7');
    expect(persisted.payload['medicationVersion'], 3);
    expect(persisted.payload['status'], 'active');

    client.close();
    store.close();
  });

  test('durable client fails closed before canonical runtime adoption', () async {
    final client = DurableLifeMateApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'token',
      accountId: () => 'legacy-auth-a',
      innerHttpClient: _StatusClient(200),
    );

    await expectLater(
      () => client.enqueueTreatmentPlanEdit(
        treatmentPlanId: '123e4567-e89b-42d3-a456-426614174071',
        version: 1,
        medicationVersion: 1,
        medicationName: 'Example',
        doseText: '1 tablet',
        startDate: DateTime(2026, 9, 5),
        timeZone: 'Asia/Tehran',
        schedules: const <Map<String, String>>[
          <String, String>{'dayOfWeek': 'saturday', 'localTime': '08:00'},
        ],
        patientReminderMinutesBefore: 15,
        caregiverReminderMinutesBefore: 30,
        status: 'active',
      ),
      throwsStateError,
    );
    client.close();
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

final class _StatusClient extends http.BaseClient {
  _StatusClient(this.statusCode);

  final int statusCode;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(const Stream<List<int>>.empty(), statusCode);
}
