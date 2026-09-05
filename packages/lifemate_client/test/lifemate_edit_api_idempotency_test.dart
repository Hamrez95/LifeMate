import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test('treatment edit preserves caller-owned idempotency key', () async {
    const requestId = '123e4567-e89b-42d3-a456-426614174777';
    final keys = <String?>[];
    var attempts = 0;
    final api = LifeMateEditApi(
      baseUri: Uri.parse('https://api.example.test/functions/v1/lifemate-api'),
      accessToken: () => 'token',
      httpClient: MockClient((request) async {
        attempts += 1;
        keys.add(request.headers['idempotency-key']);
        if (attempts == 1) {
          throw http.ClientException('response lost', request.url);
        }
        return http.Response(
          jsonEncode({
            'id': '123e4567-e89b-42d3-a456-426614174701',
            'version': 8,
            'medication': {'version': 5},
          }),
          200,
        );
      }),
    );

    final result = await api.updateTreatmentPlan(
      treatmentPlanId: '123e4567-e89b-42d3-a456-426614174701',
      version: 7,
      medicationVersion: 4,
      medicationName: 'Medication A',
      doseText: '1 tablet',
      startDate: DateTime(2026, 9, 5),
      timeZone: 'Asia/Tehran',
      schedules: const <Map<String, String>>[
        <String, String>{'dayOfWeek': 'saturday', 'localTime': '08:00'},
      ],
      patientReminderMinutesBefore: 15,
      caregiverReminderMinutesBefore: 30,
      status: 'active',
      clientRequestId: requestId,
    );

    expect(attempts, 2);
    expect(keys, <String?>[requestId, requestId]);
    expect(result['version'], 8);
  });
}
