import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_core/lifemate_core.dart';

void main() {
  const requestId = '123e4567-e89b-42d3-a456-426614174700';

  test('pregnancy calendar replay wraps the canonical care-event payload', () {
    final mutation = LifeMateOfflinePregnancyCalendarMutation.buildCreate(
      mutationId: requestId,
      classification: ' ultrasound ',
      eventType: 'appointment',
      title: 'Anatomy scan',
      providerName: 'Clinic',
      scheduledLocalDate: DateTime(2026, 9, 21),
      scheduledLocalTime: '10:30',
      timeZone: 'Asia/Tehran',
      patientReminderMinutesBefore: 30,
      caregiverReminderMinutesBefore: 0,
      createdAtUtc: DateTime.utc(2026, 9, 17, 18),
    );

    expect(mutation.mutationId, requestId);
    expect(mutation.domain, LifeMateMutationDomain.careEvent);
    expect(mutation.sourceKey, 'pregnancy-care-event-create:$requestId');
    expect(mutation.endpointPath, '/api/v1/cocoon/pregnancy/calendar/events');
    expect(mutation.method, 'POST');
    expect(mutation.payload['classification'], 'ultrasound');

    final careEvent = mutation.payload['careEvent'] as Map<String, dynamic>;
    expect(careEvent['clientRequestId'], requestId);
    expect(careEvent['eventType'], 'appointment');
    expect(careEvent['title'], 'Anatomy scan');
    expect(careEvent['scheduledLocalDate'], '2026-09-21');
    expect(careEvent['scheduledLocalTime'], '10:30');
    expect(careEvent['timeZone'], 'Asia/Tehran');
    expect(careEvent['patientReminderMinutesBefore'], 30);
    expect(careEvent['caregiverReminderMinutesBefore'], 0);
    expect(careEvent['recurrence'], const <String, dynamic>{
      'version': 2,
      'enabled': false,
    });
  });

  test('pregnancy calendar replay rejects unsupported classification', () {
    expect(
      () => LifeMateOfflinePregnancyCalendarMutation.buildCreate(
        mutationId: requestId,
        classification: 'invented',
        eventType: 'appointment',
        title: 'Visit',
        scheduledLocalDate: DateTime(2026, 9, 21),
        scheduledLocalTime: '10:30',
        timeZone: 'Asia/Tehran',
        patientReminderMinutesBefore: 30,
        caregiverReminderMinutesBefore: 0,
      ),
      throwsArgumentError,
    );
  });

  test('pregnancy calendar replay reuses canonical care-event validation', () {
    expect(
      () => LifeMateOfflinePregnancyCalendarMutation.buildCreate(
        mutationId: requestId,
        classification: 'prenatal',
        eventType: 'appointment',
        title: 'Visit',
        scheduledLocalDate: DateTime(2026, 9, 21),
        scheduledLocalTime: 'not-a-time',
        timeZone: 'Asia/Tehran',
        patientReminderMinutesBefore: 30,
        caregiverReminderMinutesBefore: 0,
      ),
      throwsArgumentError,
    );
  });
}
