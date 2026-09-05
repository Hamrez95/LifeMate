import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_core/lifemate_core.dart';

void main() {
  const planId = '11111111-1111-4111-8111-111111111111';

  test('builds exact versioned treatment PATCH without credentials', () {
    final mutation = LifeMateOfflineTreatmentMutation.buildEdit(
      mutationId: 'edit-plan-1',
      treatmentPlanId: planId,
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
        {'dayOfWeek': 'friday', 'localTime': '20:00'},
      ],
      patientReminderMinutesBefore: 30,
      caregiverReminderMinutesBefore: 60,
      status: 'active',
      createdAtUtc: DateTime.utc(2026, 9, 5, 6),
    );

    expect(mutation.domain, LifeMateMutationDomain.treatment);
    expect(
      mutation.conflictPolicy,
      LifeMateMutationConflictPolicy.explicitVersionResolution,
    );
    expect(mutation.sourceKey, planId);
    expect(mutation.method, 'PATCH');
    expect(mutation.endpointPath, '/api/v1/treatment-plans/$planId');
    expect(mutation.expectedRevision, '7');
    expect(mutation.payload['version'], 7);
    expect(mutation.payload['medicationVersion'], 3);
    expect(mutation.payload['startDate'], '2026-09-05');
    expect(mutation.payload['endDate'], '2026-09-20');
    expect(mutation.payload['status'], 'active');
    expect(mutation.payload.containsKey('authorization'), isFalse);
    expect(mutation.payload.containsKey('token'), isFalse);
  });

  test('refuses malformed plan IDs and unsupported status values', () {
    expect(() => _build(treatmentPlanId: '../escape'), throwsArgumentError);
    expect(() => _build(status: 'paused-by-guess'), throwsArgumentError);
  });

  test('refuses invalid local schedules and reversed date windows', () {
    expect(
      () => _build(
        schedules: const <Map<String, String>>[
          {'dayOfWeek': 'monday', 'localTime': '25:00'},
        ],
      ),
      throwsArgumentError,
    );
    expect(
      () => _build(
        startDate: DateTime(2026, 9, 10),
        endDate: DateTime(2026, 9, 9),
      ),
      throwsArgumentError,
    );
  });

  test('never infers or alters caller supplied medication timing', () {
    final mutation = _build(
      schedules: const <Map<String, String>>[
        {'dayOfWeek': 'tuesday', 'localTime': '07:45'},
      ],
    );

    expect(mutation.payload['schedules'], const <Map<String, String>>[
      {'dayOfWeek': 'tuesday', 'localTime': '07:45'},
    ]);
  });
}

LifeMateDurableMutation _build({
  String treatmentPlanId = '11111111-1111-4111-8111-111111111111',
  String status = 'active',
  DateTime? startDate,
  DateTime? endDate,
  List<Map<String, String>> schedules = const <Map<String, String>>[
    {'dayOfWeek': 'monday', 'localTime': '08:00'},
  ],
}) => LifeMateOfflineTreatmentMutation.buildEdit(
  mutationId: 'edit-plan-test',
  treatmentPlanId: treatmentPlanId,
  version: 2,
  medicationVersion: 1,
  medicationName: 'Medication',
  doseText: '1 tablet',
  startDate: startDate ?? DateTime(2026, 9, 5),
  endDate: endDate,
  timeZone: 'Europe/Berlin',
  schedules: schedules,
  patientReminderMinutesBefore: 30,
  caregiverReminderMinutesBefore: 60,
  status: status,
  createdAtUtc: DateTime.utc(2026, 9, 5, 6),
);
