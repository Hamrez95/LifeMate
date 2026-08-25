import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test('appointment reuse copies editable facts but not identity or status', () {
    final source = <String, dynamic>{
      'id': 'old-id',
      'version': 9,
      'status': 'completed',
      'patientUserId': 'owner-id',
      'title': 'ویزیت قلب',
      'eventType': 'appointment',
      'providerName': 'دکتر راد',
      'specialty': 'قلب',
      'centerName': 'کلینیک امید',
      'timeZone': 'Asia/Tehran',
      'recurrence': {'enabled': false},
      'patientReminderMinutesBefore': 1440,
      'caregiverReminderMinutesBefore': 2880,
    };

    final draft = CareEventReuseDraft.fromHistory(source);
    expect(draft.title, 'ویزیت قلب');
    expect(draft.providerName, 'دکتر راد');
    expect(draft.centerName, 'کلینیک امید');
    expect(draft.patientReminderMinutesBefore, 1440);
    expect(draft.eventType, 'appointment');
  });

  test('injection reuse preserves treatment facts without completion state', () {
    final draft = CareEventReuseDraft.fromHistory({
      'eventType': 'injection',
      'title': 'B12',
      'medicationName': 'B12',
      'doseText': '1 ampoule',
      'administrationRoute': 'intramuscular',
      'status': 'missed',
      'occurrenceId': 'historical-occurrence',
      'timeZone': 'Europe/Berlin',
    });
    expect(draft.medicationName, 'B12');
    expect(draft.doseText, '1 ampoule');
    expect(draft.administrationRoute, 'intramuscular');
  });

  test('reuse keeps recurrence pattern but drops historical end date', () {
    final draft = CareEventReuseDraft.fromHistory({
      'eventType': 'appointment',
      'title': 'Follow-up',
      'recurrence': {
        'enabled': true,
        'unit': 'month',
        'interval': 3,
        'endDate': '2025-01-01',
        'maxOccurrences': 4,
      },
    });

    expect(draft.recurrence.enabled, isTrue);
    expect(draft.recurrence.unit, RecurrenceUnit.month);
    expect(draft.recurrence.interval, 3);
    expect(draft.recurrence.maxOccurrences, 4);
    expect(draft.recurrence.endDate, isNull);
  });

  test('treatment reuse creates an independent immutable schedule copy', () {
    final source = <String, dynamic>{
      'id': 'plan-old',
      'version': 12,
      'status': 'stopped',
      'doseText': '1 tablet',
      'medication': {
        'id': 'med-old',
        'version': 7,
        'name': 'Vitamin D',
        'strengthText': '1000 IU',
        'form': 'tablet',
      },
      'schedules': [
        {'dayOfWeek': 'monday', 'localTime': '08:00'},
      ],
      'timeZone': 'Asia/Tehran',
    };

    final draft = TreatmentReuseDraft.fromHistory(source);
    expect(draft.medicationName, 'Vitamin D');
    expect(draft.strengthText, '1000 IU');
    expect(draft.schedules, [
      {'dayOfWeek': 'monday', 'localTime': '08:00'},
    ]);

    (source['schedules'] as List).clear();
    expect(draft.schedules, isNotEmpty);
  });

  test('invalid historical event type fails closed', () {
    expect(
      () => CareEventReuseDraft.fromHistory({
        'eventType': 'unknown',
        'title': 'x',
      }),
      throwsFormatException,
    );
  });
}
