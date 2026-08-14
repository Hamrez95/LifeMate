import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test('health record grant sends explicit consent contract', () async {
    late http.Request request;
    final api = LifeMateCareManagementApi(
      baseUri: Uri.parse(
        'https://example.supabase.co/functions/v1/lifemate-care-management',
      ),
      accessToken: () => 'token',
      httpClient: MockClient((incoming) async {
        request = incoming;
        return http.Response(
          jsonEncode({'canManageHealthRecord': true}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final result = await api.updateHealthRecordPermission(
      relationshipId: '11111111-1111-4111-8111-111111111111',
      enabled: true,
      confirmConsent: true,
    );

    expect(result['canManageHealthRecord'], isTrue);
    expect(request.method, 'PATCH');
    expect(request.headers['idempotency-key'], isNotEmpty);
    expect(
      request.url.path,
      '/functions/v1/lifemate-care-management/api/v1/relationships/'
      '11111111-1111-4111-8111-111111111111/health-record-permission',
    );
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    expect(body['canManageHealthRecord'], isTrue);
    expect(body['confirmConsent'], isTrue);
    expect(body['consentVersion'], 'health-record-management-consent-v1');
  });

  test(
    'caregiver treatment delete uses patient-scoped endpoint and version',
    () async {
      late http.Request request;
      final api = LifeMateCareManagementApi(
        baseUri: Uri.parse('https://api.example.test/lifemate-care-management'),
        accessToken: () => 'token',
        httpClient: MockClient((incoming) async {
          request = incoming;
          return http.Response('', 204);
        }),
      );

      await api.deleteTreatmentPlan(
        patientUserId: '22222222-2222-4222-8222-222222222222',
        treatmentPlanId: '33333333-3333-4333-8333-333333333333',
        version: 4,
      );

      expect(request.method, 'DELETE');
      expect(request.headers['idempotency-key'], isNotEmpty);
      expect(
        request.url.path,
        '/lifemate-care-management/api/v1/patients/'
        '22222222-2222-4222-8222-222222222222/treatment-plans/'
        '33333333-3333-4333-8333-333333333333',
      );
      expect(jsonDecode(request.body), {'version': 4});
    },
  );

  test(
    'caregiver treatment create retries with one stable idempotency key',
    () async {
      var attempts = 0;
      final keys = <String?>[];
      final api = LifeMateCareManagementApi(
        baseUri: Uri.parse('https://api.example.test/lifemate-care-management'),
        accessToken: () => 'token',
        httpClient: MockClient((request) async {
          attempts += 1;
          keys.add(request.headers['idempotency-key']);
          if (attempts == 1) {
            throw http.ClientException('response lost', request.url);
          }
          return http.Response(
            jsonEncode({'id': 'plan-1', 'version': 1}),
            201,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final result = await api.createTreatmentPlan(
        patientUserId: '22222222-2222-4222-8222-222222222222',
        medicationName: 'Metformin',
        doseText: '500 mg',
        startDate: DateTime(2026, 8, 14),
        timeZone: 'Asia/Tehran',
        schedules: const [
          {'dayOfWeek': 'friday', 'localTime': '08:00'},
        ],
      );

      expect(attempts, 2);
      expect(keys.first, isNotNull);
      expect(keys[1], keys.first);
      expect(result['id'], 'plan-1');
    },
  );

  test(
    'caregiver care event uses client request id as transport key',
    () async {
      late http.Request request;
      final api = LifeMateCareManagementApi(
        baseUri: Uri.parse('https://api.example.test/lifemate-care-management'),
        accessToken: () => 'token',
        httpClient: MockClient((incoming) async {
          request = incoming;
          return http.Response(
            jsonEncode({'id': 'event-1', 'version': 1}),
            201,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      const requestId = '11111111-1111-4111-8111-111111111137';

      await api.createCareEvent(
        patientUserId: '22222222-2222-4222-8222-222222222222',
        clientRequestId: requestId,
        eventType: 'appointment',
        title: 'Checkup',
        scheduledLocalDate: DateTime(2026, 8, 14),
        scheduledLocalTime: '12:00',
        timeZone: 'Asia/Tehran',
      );

      expect(request.headers['idempotency-key'], requestId);
    },
  );

  test('care management base URI preserves candidate environment suffix', () {
    expect(
      LifeMateCareManagementApi.managementBaseUriFor(
        Uri.parse(
          'https://example.supabase.co/functions/v1/lifemate-api-candidate',
        ),
      ).toString(),
      'https://example.supabase.co/functions/v1/lifemate-care-management-candidate',
    );
    expect(
      LifeMateCareManagementApi.managementBaseUriFor(
        Uri.parse('https://example.supabase.co/functions/v1/lifemate-api'),
      ).toString(),
      'https://example.supabase.co/functions/v1/lifemate-care-management',
    );
  });
}
