import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:lifemate_core/lifemate_core.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final key = Uint8List.fromList(List<int>.generate(32, (index) => index + 1));

  test('calendar retry uses the owner Person outbox and one stable request id', () async {
    final store = LifeMateLocalHealthStore.forTesting(
      database: sqlite3.openInMemory(),
      keyBytes: key,
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
    final coordinator = _coordinator(store, identityStore: identityStore);

    const requestId = '123e4567-e89b-42d3-a456-426614174700';
    Future<void> enqueue({String title = 'Prenatal visit'}) =>
        coordinator.enqueueCalendarEvent(
          clientRequestId: requestId,
          classification: 'prenatal',
          eventType: 'appointment',
          title: title,
          providerName: 'Clinic',
          scheduledLocalDate: DateTime(2026, 9, 21),
          scheduledLocalTime: '10:30',
          patientReminderMinutesBefore: 30,
          caregiverReminderMinutesBefore: 0,
        );

    await enqueue();
    await enqueue();

    expect(await coordinator.pendingPregnancyMutationIds(), <String>{requestId});
    final outbox = LifeMateLocalMutationOutbox(store: store);
    final queued = await outbox.list(
      namespace: LifeMateLocalNamespace(
        environmentId: 'https://api.example.test',
        accountId: 'account-a',
        personId: 'person-a',
      ),
    );
    expect(queued, hasLength(1));
    final mutation = queued.single;
    expect(mutation.domain, LifeMateMutationDomain.careEvent);
    expect(mutation.endpointPath, '/api/v1/cocoon/pregnancy/calendar/events');
    expect(mutation.mutationId, requestId);
    expect(mutation.payload['classification'], 'prenatal');
    final careEvent = mutation.payload['careEvent'] as Map<String, dynamic>;
    expect(careEvent['clientRequestId'], requestId);
    expect(careEvent['scheduledLocalDate'], '2026-09-21');
    expect(careEvent['scheduledLocalTime'], '10:30');
    expect(careEvent['timeZone'], 'Asia/Tehran');
    expect(careEvent['caregiverReminderMinutesBefore'], 0);

    await expectLater(enqueue(title: 'Different visit'), throwsStateError);
    expect(await coordinator.pendingPregnancyMutationIds(), <String>{requestId});
  });

  test('calendar write requires adopted owner identity before local acceptance', () async {
    final store = LifeMateLocalHealthStore.forTesting(
      database: sqlite3.openInMemory(),
      keyBytes: key,
    );
    addTearDown(store.close);
    final coordinator = _coordinator(store);

    await expectLater(
      coordinator.enqueueCalendarEvent(
        clientRequestId: '123e4567-e89b-42d3-a456-426614174701',
        classification: 'prenatal',
        eventType: 'appointment',
        title: 'Prenatal visit',
        scheduledLocalDate: DateTime(2026, 9, 21),
        scheduledLocalTime: '10:30',
        patientReminderMinutesBefore: 30,
        caregiverReminderMinutesBefore: 0,
      ),
      throwsStateError,
    );
  });
}

CocoonPregnancyOfflineOwnerCoordinator _coordinator(
  LifeMateLocalHealthStore store, {
  LifeMateOfflineIdentityAdoptionStore? identityStore,
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
  identityStore:
      identityStore ??
      LifeMateOfflineIdentityAdoptionStore.forTesting(_MemoryIdentityStorage()),
  localStore: store,
);

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
