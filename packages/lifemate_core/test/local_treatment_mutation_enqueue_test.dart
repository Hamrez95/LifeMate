import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_core/lifemate_core.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  final namespace = LifeMateLocalNamespace(
    environmentId: 'test-environment',
    accountId: 'account-a',
    personId: 'person-a',
  );
  final key = List<int>.generate(32, (index) => index + 1);
  const planId = '11111111-2222-4333-8444-555555555555';

  test(
    'validated treatment edit is durably queued with expected revision',
    () async {
      final store = LifeMateLocalHealthStore.forTesting(
        database: sqlite3.openInMemory(),
        keyBytes: key,
      );
      addTearDown(store.close);
      final outbox = LifeMateLocalMutationOutbox(store: store);

      final mutation = await LifeMateOfflineTreatmentMutation.enqueueEdit(
        outbox: outbox,
        namespace: namespace,
        mutationId: 'treatment-edit-1',
        treatmentPlanId: planId,
        version: 7,
        medicationVersion: 3,
        medicationName: 'Vitamin D',
        strengthText: '1000 IU',
        form: 'tablet',
        doseText: '1 tablet',
        instructions: 'after breakfast',
        startDate: DateTime(2026, 9, 5),
        timeZone: 'Asia/Tehran',
        schedules: const <Map<String, String>>[
          <String, String>{'dayOfWeek': 'monday', 'localTime': '08:30'},
        ],
        patientReminderMinutesBefore: 10,
        caregiverReminderMinutesBefore: 15,
        status: 'active',
        createdAtUtc: DateTime.utc(2026, 9, 5, 6),
      );

      expect(mutation.domain, LifeMateMutationDomain.treatment);
      expect(mutation.endpointPath, '/api/v1/treatment-plans/$planId');
      expect(mutation.expectedRevision, '7');

      final queued = await outbox.get(
        namespace: namespace,
        mutationId: 'treatment-edit-1',
      );
      expect(queued, isNotNull);
      expect(queued?.state, LifeMateMutationSyncState.pending);
      expect(queued?.payload['version'], 7);
      expect(queued?.payload['medicationVersion'], 3);
    },
  );

  test('invalid treatment edit is rejected before any outbox write', () async {
    final store = LifeMateLocalHealthStore.forTesting(
      database: sqlite3.openInMemory(),
      keyBytes: key,
    );
    addTearDown(store.close);
    final outbox = LifeMateLocalMutationOutbox(store: store);

    await expectLater(
      () => LifeMateOfflineTreatmentMutation.enqueueEdit(
        outbox: outbox,
        namespace: namespace,
        mutationId: 'invalid-edit',
        treatmentPlanId: planId,
        version: 7,
        medicationVersion: 3,
        medicationName: 'Vitamin D',
        doseText: '1 tablet',
        startDate: DateTime(2026, 9, 5),
        timeZone: 'Asia/Tehran',
        schedules: const <Map<String, String>>[
          <String, String>{'dayOfWeek': 'monday', 'localTime': '25:30'},
        ],
        patientReminderMinutesBefore: 10,
        caregiverReminderMinutesBefore: 15,
        status: 'active',
      ),
      throwsArgumentError,
    );

    expect(await outbox.list(namespace: namespace), isEmpty);
  });
}
