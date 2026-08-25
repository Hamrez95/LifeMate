import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test('reused appointment remains a fresh editable draft', () {
    final source = <String, dynamic>{
      'id': 'historical-id',
      'version': 11,
      'status': 'completed',
      'eventType': 'appointment',
      'title': 'Cardiology follow-up',
      'providerName': 'Dr. Rad',
      'centerName': 'Omid Clinic',
      'scheduledLocalDate': '2025-01-10',
      'scheduledLocalTime': '08:30',
      'recurrence': {
        'enabled': true,
        'unit': 'month',
        'interval': 6,
        'endDate': '2025-07-10',
      },
    };

    final draft = CareEventReuseDraft.fromHistory(source);
    expect(draft.title, 'Cardiology follow-up');
    expect(draft.providerName, 'Dr. Rad');
    expect(draft.centerName, 'Omid Clinic');
    expect(draft.recurrence.enabled, isTrue);
    expect(draft.recurrence.endDate, isNull);
  });

  test('historical identity and completion metadata have no draft fields', () {
    final draft = TreatmentReuseDraft.fromHistory({
      'id': 'old-plan',
      'version': 4,
      'status': 'stopped',
      'adherence': 'missed',
      'medication': {'name': 'Cetirizine', 'form': 'tablet'},
      'doseText': '1 tablet',
    });

    expect(draft.medicationName, 'Cetirizine');
    expect(draft.doseText, '1 tablet');
  });
}
