import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test('loads an owned care event with bearer authentication', () async {
    late http.Request captured;
    final api = LifeMateEditApi(
      baseUri: Uri.parse('https://api.example.test/functions/v1/lifemate-api'),
      accessToken: () => 'access-token',
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'id': 'event-1',
            'eventType': 'appointment',
            'title': 'ویزیت',
            'version': 2,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final result = await api.getCareEvent(eventId: 'event-1');

    expect(result['version'], 2);
    expect(captured.method, 'GET');
    expect(
      captured.url.toString(),
      'https://api.example.test/functions/v1/lifemate-api/api/v1/care-events/event-1',
    );
    expect(captured.headers['authorization'], 'Bearer access-token');
  });

  test('sends optimistic treatment edit payload', () async {
    late http.Request captured;
    final api = LifeMateEditApi(
      baseUri: Uri.parse('https://api.example.test/functions/v1/lifemate-api'),
      accessToken: () => 'token',
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'id': 'plan-1',
            'version': 5,
            'medication': {'version': 3},
          }),
          200,
        );
      }),
    );

    await api.updateTreatmentPlan(
      treatmentPlanId: 'plan-1',
      version: 4,
      medicationVersion: 2,
      medicationName: 'سیتریزین',
      strengthText: '10 mg',
      form: 'tablet',
      doseText: '1 tablet',
      instructions: 'after food',
      startDate: DateTime(2026, 8, 5),
      endDate: null,
      timeZone: 'Asia/Tehran',
      schedules: const [
        {'dayOfWeek': 'monday', 'localTime': '08:00'},
      ],
      patientReminderMinutesBefore: 30,
      caregiverReminderMinutesBefore: 60,
      status: 'active',
    );

    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(captured.method, 'PATCH');
    expect(body['version'], 4);
    expect(body['medicationVersion'], 2);
    expect(body['medicationName'], 'سیتریزین');
    expect(body['startDate'], '2026-08-05');
    expect(body['endDate'], isNull);
    expect(body['patientReminderMinutesBefore'], 30);
    expect((body['schedules'] as List).single['localTime'], '08:00');
  });

  test('maps stale care event response to LifeMateApiException', () async {
    final api = LifeMateEditApi(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'token',
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'code': 'stale_care_event',
            'message': 'Care event has changed.',
          }),
          409,
        ),
      ),
    );

    expect(
      () => api.updateCareEvent(
        eventId: 'event-1',
        version: 1,
        eventType: 'appointment',
        title: 'visit',
        scheduledLocalDate: DateTime(2026, 8, 5),
        scheduledLocalTime: '12:30',
        timeZone: 'Asia/Tehran',
        patientReminderMinutesBefore: 30,
        caregiverReminderMinutesBefore: 60,
        status: 'scheduled',
      ),
      throwsA(
        isA<LifeMateApiException>()
            .having((error) => error.statusCode, 'statusCode', 409)
            .having((error) => error.code, 'code', 'stale_care_event'),
      ),
    );
  });
}
