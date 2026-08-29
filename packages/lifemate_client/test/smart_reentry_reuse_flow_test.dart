import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test('smart suggestion payload flows through existing register-again prefill', () {
    const source = <String, dynamic>{
      'eventType': 'appointment',
      'title': 'ویزیت دوره‌ای',
      'providerName': 'دکتر سارا راد',
      'specialty': 'داخلی',
      'centerName': 'کلینیک امید',
      'timeZone': 'Asia/Tehran',
      'patientReminderMinutesBefore': 30,
      'caregiverReminderMinutesBefore': 60,
      'recurrence': {'enabled': false},
      'scheduledLocalDate': '2026-06-28',
      'scheduledLocalTime': '10:00',
      'status': 'missed',
    };

    final suggestion = SmartReentrySuggestion(
      patternKey: 'appointment:dr-rad',
      kind: SmartReentryKind.appointment,
      identityKey: 'dr-rad',
      latestSource: source,
      latestOccurredOn: DateTime(2026, 6, 28),
      averageIntervalDays: 60,
      reasonDaysAgo: 62,
    );
    final draft = CareEventReuseDraft.fromHistory(suggestion.latestSource);

    expect(draft.eventType, 'appointment');
    expect(draft.providerName, 'دکتر سارا راد');
    expect(draft.centerName, 'کلینیک امید');
    expect(draft.recurrence.enabled, isFalse);
    expect(suggestion.latestSource.containsKey('clientRequestId'), isFalse);
  });
}
