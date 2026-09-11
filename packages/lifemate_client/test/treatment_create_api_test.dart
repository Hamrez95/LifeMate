import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test('atomic treatment create sends one nested medication mutation', () async {
    late http.Request observed;
    final api = LifeMateTreatmentCreateApi(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'access-token',
      httpClient: MockClient((request) async {
        observed = request;
        return http.Response(
          jsonEncode(<String, dynamic>{
            'id': 'plan-1',
            'medication': <String, dynamic>{'id': 'med-1'},
          }),
          201,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(api.close);

    final result = await api.createTreatment(
      clientRequestId: 'atomic-treatment-1',
      medicationName: ' Acetaminophen ',
      strengthText: '500 mg',
      form: 'tablet',
      medicationNotes: 'after food',
      doseText: '1 tablet',
      instructions: 'after food',
      startDate: DateTime(2026, 9, 11),
      endDate: DateTime(2026, 9, 20),
      timeZone: 'Asia/Tehran',
      schedules: const <Map<String, String>>[],
      recurrence: RecurrenceRule(
        enabled: true,
        unit: RecurrenceUnit.hour,
        interval: 8,
        endDate: DateTime(2026, 9, 20, 23, 59, 59),
      ),
      recurrenceStartLocalTime: '09:15',
    );

    expect(result['id'], 'plan-1');
    expect(observed.method, 'POST');
    expect(
      observed.url.toString(),
      'https://api.example.test/api/v1/treatment-plans',
    );
    expect(observed.headers['idempotency-key'], 'atomic-treatment-1');
    expect(observed.headers['authorization'], 'Bearer access-token');

    final body = jsonDecode(observed.body) as Map<String, dynamic>;
    expect(body.containsKey('medicationId'), isFalse);
    expect(body['clientRequestId'], 'atomic-treatment-1');
    expect(
      body['medication'],
      <String, dynamic>{
        'name': 'Acetaminophen',
        'strengthText': '500 mg',
        'form': 'tablet',
        'notes': 'after food',
      },
    );
    expect(body['doseText'], '1 tablet');
    expect(body['timeZone'], 'Asia/Tehran');
    expect(body['schedules'], isEmpty);
    expect(body['recurrenceStartLocalTime'], '09:15');
    final recurrence = body['recurrence'] as Map<String, dynamic>;
    expect(recurrence['enabled'], isTrue);
    expect(recurrence['unit'], 'hour');
    expect(recurrence['interval'], 8);
  });

  test('atomic treatment create preserves correlation id on backend failure', () async {
    final api = LifeMateTreatmentCreateApi(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'access-token',
      httpClient: MockClient((request) async {
        return http.Response(
          jsonEncode(<String, dynamic>{
            'code': 'treatment_plan_invalid',
            'detail': 'Synthetic validation failure.',
            'correlationId': 'corr-treatment-42',
          }),
          422,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(api.close);

    await expectLater(
      api.createTreatment(
        clientRequestId: 'atomic-treatment-2',
        medicationName: 'Example',
        form: 'tablet',
        doseText: '1 tablet',
        startDate: DateTime(2026, 9, 11),
        timeZone: 'Asia/Tehran',
        schedules: const <Map<String, String>>[
          <String, String>{'dayOfWeek': 'friday', 'localTime': '09:00'},
        ],
      ),
      throwsA(
        isA<LifeMateApiException>()
            .having((error) => error.statusCode, 'statusCode', 422)
            .having((error) => error.code, 'code', 'treatment_plan_invalid')
            .having(
              (error) => error.correlationId,
              'correlationId',
              'corr-treatment-42',
            ),
      ),
    );
  });

  test('atomic treatment create requires a recurrence anchor', () async {
    final api = LifeMateTreatmentCreateApi(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'access-token',
      httpClient: MockClient((request) async => http.Response('{}', 201)),
    );
    addTearDown(api.close);

    await expectLater(
      api.createTreatment(
        clientRequestId: 'atomic-treatment-3',
        medicationName: 'Example',
        doseText: '1 tablet',
        startDate: DateTime(2026, 9, 11),
        timeZone: 'Asia/Tehran',
        schedules: const <Map<String, String>>[],
        recurrence: const RecurrenceRule(
          enabled: true,
          unit: RecurrenceUnit.hour,
          interval: 8,
        ),
      ),
      throwsArgumentError,
    );
  });
}
