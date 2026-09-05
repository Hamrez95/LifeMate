import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_core/lifemate_core.dart';

void main() {
  const requestId = '123e4567-e89b-42d3-a456-426614174832';

  test('builds exact idempotent appointment create without credentials', () {
    final mutation = LifeMateOfflineCareEventMutation.buildCreate(
      mutationId: requestId,
      eventType: 'appointment',
      title: 'Cardiology follow-up',
      providerName: 'Doctor',
      specialty: 'Cardiology',
      reason: 'Follow-up',
      instructions: 'Bring prior results',
      centerName: 'Clinic',
      addressLine: 'Address',
      phoneNumber: '02100000000',
      scheduledLocalDate: DateTime(2026, 9, 6),
      scheduledLocalTime: '09:30',
      timeZone: 'Asia/Tehran',
      patientReminderMinutesBefore: 30,
      caregiverReminderMinutesBefore: 60,
      createdAtUtc: DateTime.utc(2026, 9, 5, 8),
    );

    expect(mutation.domain, LifeMateMutationDomain.careEvent);
    expect(
      mutation.conflictPolicy,
      LifeMateMutationConflictPolicy.explicitVersionResolution,
    );
    expect(mutation.sourceKey, 'pending-care-event-create:$requestId');
    expect(mutation.method, 'POST');
    expect(mutation.endpointPath, '/api/v1/care-events');
    expect(mutation.expectedRevision, isNull);
    expect(mutation.payload['clientRequestId'], requestId);
    expect(mutation.payload['eventType'], 'appointment');
    expect(mutation.payload['scheduledLocalDate'], '2026-09-06');
    expect(mutation.payload['scheduledLocalTime'], '09:30');
    expect(mutation.payload['timeZone'], 'Asia/Tehran');
    expect(mutation.payload['recurrence'], const <String, dynamic>{
      'version': 2,
      'enabled': false,
    });
    expect(mutation.payload.containsKey('authorization'), isFalse);
    expect(mutation.payload.containsKey('token'), isFalse);
  });

  test('builds injection without changing route, timing or reminder leads', () {
    final mutation = LifeMateOfflineCareEventMutation.buildCreate(
      mutationId: requestId,
      eventType: 'injection',
      title: 'Injection',
      medicationName: 'Medication',
      doseText: '1 ampoule',
      administrationRoute: 'intramuscular',
      scheduledLocalDate: DateTime(2026, 9, 7),
      scheduledLocalTime: '14:05',
      timeZone: 'Asia/Tehran',
      patientReminderMinutesBefore: 45,
      caregiverReminderMinutesBefore: 90,
    );

    expect(mutation.payload['medicationName'], 'Medication');
    expect(mutation.payload['administrationRoute'], 'intramuscular');
    expect(mutation.payload['scheduledLocalTime'], '14:05');
    expect(mutation.payload['patientReminderMinutesBefore'], 45);
    expect(mutation.payload['caregiverReminderMinutesBefore'], 90);
  });

  test('rejects recurrence-adjacent unsafe or malformed create inputs', () {
    expect(() => _build(mutationId: 'not-a-server-uuid'), throwsArgumentError);
    expect(() => _build(eventType: 'unknown'), throwsArgumentError);
    expect(
      () => _build(eventType: 'injection', medicationName: null),
      throwsArgumentError,
    );
    expect(() => _build(scheduledLocalTime: '25:00'), throwsArgumentError);
    expect(
      () => _build(patientReminderMinutesBefore: 10081),
      throwsArgumentError,
    );
    expect(
      () => _build(administrationRoute: 'guessed-route'),
      throwsArgumentError,
    );
  });
}

LifeMateDurableMutation _build({
  String mutationId = '123e4567-e89b-42d3-a456-426614174832',
  String eventType = 'appointment',
  String? medicationName,
  String scheduledLocalTime = '08:00',
  String? administrationRoute,
  int patientReminderMinutesBefore = 30,
}) => LifeMateOfflineCareEventMutation.buildCreate(
  mutationId: mutationId,
  eventType: eventType,
  title: 'Care event',
  medicationName: medicationName,
  administrationRoute: administrationRoute,
  scheduledLocalDate: DateTime(2026, 9, 6),
  scheduledLocalTime: scheduledLocalTime,
  timeZone: 'Asia/Tehran',
  patientReminderMinutesBefore: patientReminderMinutesBefore,
  caregiverReminderMinutesBefore: 60,
);
