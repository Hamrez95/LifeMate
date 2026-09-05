import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:wellmate/screens/treatments/offline_treatment_create.dart';

void main() {
  test('only bounded transient network failures are eligible', () {
    for (final code in <String>[
      'network_unavailable',
      'network_timeout',
      'retry_budget_exhausted',
    ]) {
      expect(
        isTransientTreatmentCreateFailure(
          LifeMateApiException(statusCode: 0, code: code, message: 'safe'),
        ),
        isTrue,
      );
    }

    for (final failure in <(int, String)>[
      (401, 'unauthorized'),
      (403, 'forbidden'),
      (409, 'conflict'),
      (422, 'validation_failed'),
      (500, 'unexpected_server_error'),
    ]) {
      expect(
        isTransientTreatmentCreateFailure(
          LifeMateApiException(
            statusCode: failure.$1,
            code: failure.$2,
            message: 'do not queue',
          ),
        ),
        isFalse,
      );
    }
  });

  test('recurrence and non-durable clients never become offline success', () async {
    final api = LifeMateApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'token',
    );
    const transient = LifeMateApiException(
      statusCode: 0,
      code: 'network_timeout',
      message: 'temporary',
    );

    expect(
      await queueTreatmentCreateAfterTransientFailure(
        api: api,
        error: transient,
        clientRequestId: '123e4567-e89b-42d3-a456-426614174000',
        medicationId: '123e4567-e89b-42d3-a456-426614174700',
        doseText: '1 tablet',
        startDate: DateTime(2026, 9, 5),
        timeZone: 'Asia/Tehran',
        schedules: const <Map<String, String>>[
          <String, String>{'dayOfWeek': 'monday', 'localTime': '08:00'},
        ],
        patientReminderMinutesBefore: 15,
        caregiverReminderMinutesBefore: 30,
        recurrenceEnabled: false,
      ),
      isFalse,
    );

    expect(
      await queueTreatmentCreateAfterTransientFailure(
        api: api,
        error: transient,
        clientRequestId: '123e4567-e89b-42d3-a456-426614174001',
        medicationId: '123e4567-e89b-42d3-a456-426614174700',
        doseText: '1 tablet',
        startDate: DateTime(2026, 9, 5),
        timeZone: 'Asia/Tehran',
        schedules: const <Map<String, String>>[],
        patientReminderMinutesBefore: 15,
        caregiverReminderMinutesBefore: 30,
        recurrenceEnabled: true,
      ),
      isFalse,
    );

    api.close();
  });
}
