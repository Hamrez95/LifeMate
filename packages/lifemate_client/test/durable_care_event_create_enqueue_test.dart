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

  test('durable client enqueues exact bounded care event in adopted namespace', () async {
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

    const requestId = '123e4567-e89b-42d3-a456-426614174711';
    await api.enqueueOfflineCareEventCreate(
      clientRequestId: requestId,
      eventType: 'injection',
      title: 'Injection appointment',
      medicationName: 'Medication',
      doseText: '1 dose',
      administrationRoute: 'intramuscular',
      reason: 'Scheduled care',
      instructions: 'As prescribed',
      centerName: 'Clinic',
      scheduledLocalDate: DateTime(2026, 9, 8),
      scheduledLocalTime: '09:15',
      timeZone: 'Asia/Tehran',
      patientReminderMinutesBefore: 20,
      caregiverReminderMinutesBefore: 45,
    );

    expect(await api.pendingMutationCount(), 1);
    final stored = await LifeMateLocalMutationOutbox(store: store).get(
      namespace: namespace,
      mutationId: requestId,
    );
    expect(stored?.mutationId, requestId);
    expect(stored?.domain, LifeMateMutationDomain.careEvent);
    expect(stored?.method, 'POST');
    expect(stored?.endpointPath, '/api/v1/care-events');
    expect(stored?.sourceKey, 'pending-care-event-create:$requestId');
    expect(stored?.expectedRevision, isNull);
    expect(stored?.state, LifeMateMutationSyncState.pending);
    expect(stored?.payload['clientRequestId'], requestId);
    expect(stored?.payload['eventType'], 'injection');
    expect(stored?.payload['medicationName'], 'Medication');
    expect(stored?.payload['doseText'], '1 dose');
    expect(stored?.payload['administrationRoute'], 'intramuscular');
    expect(stored?.payload['scheduledLocalDate'], '2026-09-08');
    expect(stored?.payload['scheduledLocalTime'], '09:15');
    expect(stored?.payload['timeZone'], 'Asia/Tehran');
    expect(stored?.payload['patientReminderMinutesBefore'], 20);
    expect(stored?.payload['caregiverReminderMinutesBefore'], 45);
    expect(stored?.payload['recurrence'], <String, dynamic>{
      'version': 2,
      'enabled': false,
    });
    expect(stored?.payload.containsKey('authorization'), isFalse);
    expect(stored?.payload.containsKey('token'), isFalse);

    final otherPerson = LifeMateLocalNamespace(
      environmentId: namespace.environmentId,
      accountId: namespace.accountId,
      personId: 'person-b',
    );
    expect(
      await LifeMateLocalMutationOutbox(store: store).get(
        namespace: otherPerson,
        mutationId: requestId,
      ),
      isNull,
    );

    api.close();
    store.close();
  });

  test('care-event create enqueue fails before canonical runtime adoption', () {
    final api = DurableLifeMateApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'token',
      accountId: () => legacyAccountId,
    );

    expect(
      () => api.enqueueOfflineCareEventCreate(
        clientRequestId: '123e4567-e89b-42d3-a456-426614174712',
        eventType: 'appointment',
        title: 'Visit',
        scheduledLocalDate: DateTime(2026, 9, 9),
        scheduledLocalTime: '10:00',
        timeZone: 'Asia/Tehran',
        patientReminderMinutesBefore: 30,
        caregiverReminderMinutesBefore: 60,
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
