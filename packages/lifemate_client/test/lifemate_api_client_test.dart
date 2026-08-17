import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test('care recipient request carries auth and patient scope', () async {
    late http.Request observed;
    final api = LifeMateApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'access-token',
      httpClient: MockClient((request) async {
        observed = request;
        return http.Response(
          jsonEncode([
            {'id': 'dose-1', 'medicationName': 'Metformin', 'status': 'taken'},
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final result = await api.getCareRecipientDoseOccurrences(
      patientUserId: 'patient-1',
      fromDate: DateTime(2026, 7, 27),
      toDate: DateTime(2026, 7, 27),
    );

    expect(observed.method, 'GET');
    expect(observed.headers['authorization'], 'Bearer access-token');
    expect(
      observed.url.path,
      '/api/v1/care/patients/patient-1/dose-occurrences',
    );
    expect(observed.url.queryParameters['fromDate'], '2026-07-27');
    expect(result.single['medicationName'], 'Metformin');
  });

  test(
    'care recipient event request carries patient scope and range',
    () async {
      late http.Request observed;
      final api = LifeMateApiClient(
        baseUri: Uri.parse('https://api.example.test'),
        accessToken: () => 'access-token',
        httpClient: MockClient((request) async {
          observed = request;
          return http.Response(
            jsonEncode([
              {
                'id': 'event-1',
                'eventType': 'appointment',
                'title': 'Cardiology visit',
              },
            ]),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final result = await api.getCareRecipientCareEvents(
        patientUserId: 'patient-1',
        fromDate: DateTime(2026, 8, 3),
        toDate: DateTime(2026, 8, 10),
      );

      expect(observed.method, 'GET');
      expect(observed.url.path, '/api/v1/care/patients/patient-1/care-events');
      expect(observed.url.queryParameters['fromDate'], '2026-08-03');
      expect(observed.url.queryParameters['toDate'], '2026-08-10');
      expect(result.single['eventType'], 'appointment');
    },
  );

  test(
    'care event creation retries with an identical idempotent payload',
    () async {
      var requestCount = 0;
      final requestBodies = <String>[];
      final api = LifeMateApiClient(
        baseUri: Uri.parse('https://api.example.test'),
        accessToken: () => 'access-token',
        httpClient: MockClient((request) async {
          requestCount += 1;
          requestBodies.add(request.body);
          if (requestCount == 1) {
            throw http.ClientException('response lost', request.url);
          }
          return http.Response(
            jsonEncode({
              'id': 'event-1',
              'eventType': 'appointment',
              'title': 'Cardiology visit',
            }),
            201,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final result = await api.createCareEvent(
        clientRequestId: '33333333-3333-4333-8333-333333333333',
        eventType: 'appointment',
        title: 'Cardiology visit',
        providerName: 'Dr. Sara Rad',
        centerName: 'Heart Clinic',
        addressLine: 'Tehran, Valiasr Street',
        scheduledLocalDate: DateTime(2026, 8, 4),
        scheduledLocalTime: '16:30',
        timeZone: 'Asia/Tehran',
      );

      expect(requestCount, 2);
      expect(requestBodies[0], requestBodies[1]);
      final body = jsonDecode(requestBodies.first) as Map<String, dynamic>;
      expect(body['clientRequestId'], '33333333-3333-4333-8333-333333333333');
      expect(body['addressLine'], 'Tehran, Valiasr Street');
      expect(body['scheduledLocalTime'], '16:30');
      expect(result['eventType'], 'appointment');
    },
  );

  test('invitation acceptance sends current consent contract', () async {
    late Map<String, dynamic> body;
    final api = LifeMateApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'access-token',
      httpClient: MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({'id': 'relationship-1', 'status': 'active'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await api.acceptCareInvitation(token: ' invite-token ');

    expect(body['token'], 'invite-token');
    expect(body['consentVersion'], 'care-caregiver-consent-v1');
    expect(body['confirmConsent'], isTrue);
  });

  test('phone care invitation sends explicit patient consent without token assumptions', () async {
    late http.Request observed;
    late Map<String, dynamic> body;
    final api = LifeMateApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'access-token',
      httpClient: MockClient((request) async {
        observed = request;
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'id': 'phone-invite-1',
            'contactType': 'phone',
            'contactHint': '+98 ••• •• 5678',
            'expiresAtUtc': '2026-08-17T08:00:00.000Z',
          }),
          201,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final result = await api.createPhoneCareInvitation(
      phone: ' ۰۹۳۵ ۱۲۳ ۵۶۷۸ ',
    );

    expect(observed.method, 'POST');
    expect(observed.url.path, '/api/v1/care/invitations');
    expect(observed.headers['authorization'], 'Bearer access-token');
    expect(observed.headers['idempotency-key'], isNotEmpty);
    expect(body['contactType'], 'phone');
    expect(body['contact'], '۰۹۳۵ ۱۲۳ ۵۶۷۸');
    expect(body['consentVersion'], 'care-patient-consent-v1');
    expect(body['confirmConsent'], isTrue);
    expect(result['contactHint'], '+98 ••• •• 5678');
    expect(result.containsKey('token'), isFalse);
  });

  test('outgoing care invitation can be revoked by id', () async {
    late http.Request observed;
    final api = LifeMateApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'access-token',
      httpClient: MockClient((request) async {
        observed = request;
        return http.Response(
          jsonEncode({'id': '11111111-1111-4111-8111-111111111111'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await api.revokeCareInvitation(
      invitationId: '11111111-1111-4111-8111-111111111111',
    );

    expect(observed.method, 'DELETE');
    expect(
      observed.url.path,
      '/api/v1/care/invitations/11111111-1111-4111-8111-111111111111',
    );
    expect(observed.headers['authorization'], 'Bearer access-token');
  });

  test('caregiver care request sends caregiver consent contract', () async {
    late http.Request observed;
    late Map<String, dynamic> body;
    final api = LifeMateApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'access-token',
      httpClient: MockClient((request) async {
        observed = request;
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({'id': 'request-1', 'status': 'pending'}),
          201,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await api.createCareRequest(email: ' patient@example.com ');

    expect(observed.method, 'POST');
    expect(observed.url.path, '/api/v1/care/requests');
    expect(body['contact'], 'patient@example.com');
    expect(body['consentVersion'], 'care-caregiver-request-v1');
    expect(body['confirmConsent'], isTrue);
  });

  test('patient acceptance sends explicit patient consent', () async {
    late Map<String, dynamic> body;
    final api = LifeMateApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'access-token',
      httpClient: MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({'id': 'request-1', 'status': 'accepted'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await api.respondCareRequest(requestId: 'request-1', accept: true);

    expect(body['action'], 'accept');
    expect(body['consentVersion'], 'care-patient-consent-v1');
    expect(body['confirmConsent'], isTrue);
  });

  test('missing session fails before a network request', () async {
    var requested = false;
    final api = LifeMateApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => null,
      httpClient: MockClient((request) async {
        requested = true;
        return http.Response('[]', 200);
      }),
    );

    await expectLater(
      api.getCareRelationships(),
      throwsA(
        isA<LifeMateApiException>().having(
          (error) => error.code,
          'code',
          'session_missing',
        ),
      ),
    );
    expect(requested, isFalse);
  });

  test(
    'dose report retries one transport failure with identical payload',
    () async {
      var requestCount = 0;
      final requestBodies = <String>[];
      final api = LifeMateApiClient(
        baseUri: Uri.parse('https://api.example.test'),
        accessToken: () => 'access-token',
        httpClient: MockClient((request) async {
          requestCount += 1;
          requestBodies.add(request.body);
          if (requestCount == 1) {
            throw http.ClientException('response was lost', request.url);
          }
          return http.Response(
            jsonEncode({'id': 'dose-1', 'status': 'taken', 'version': 2}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final result = await api.reportDose(
        occurrenceId: 'dose-1',
        clientRequestId: '11111111-1111-4111-8111-111111111111',
        version: 1,
        status: 'taken',
        occurredAtUtc: DateTime.utc(2026, 7, 30, 12),
      );

      expect(requestCount, 2);
      expect(requestBodies[0], requestBodies[1]);
      expect(
        jsonDecode(requestBodies.first)['clientRequestId'],
        '11111111-1111-4111-8111-111111111111',
      );
      expect(result['status'], 'taken');
    },
  );

  test('safe GET retries one transient gateway response', () async {
    var requestCount = 0;
    final api = LifeMateApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'access-token',
      httpClient: MockClient((request) async {
        requestCount += 1;
        if (requestCount < 3) {
          return http.Response(
            jsonEncode({'code': 'database_busy'}),
            503,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode([
            {'id': 'medication-1', 'name': 'Metformin'},
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final result = await api.getMedications();

    expect(requestCount, 3);
    expect(result.single['id'], 'medication-1');
  });

  test(
    'critical creation retries with one stable generated idempotency key',
    () async {
      var requestCount = 0;
      final idempotencyKeys = <String?>[];
      final api = LifeMateApiClient(
        baseUri: Uri.parse('https://api.example.test'),
        accessToken: () => 'access-token',
        httpClient: MockClient((request) async {
          requestCount += 1;
          idempotencyKeys.add(request.headers['idempotency-key']);
          if (requestCount == 1) {
            throw http.ClientException('response lost', request.url);
          }
          return http.Response(
            jsonEncode({'id': 'medication-1', 'name': 'Metformin'}),
            201,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final result = await api.createMedication(name: 'Metformin');

      expect(requestCount, 2);
      expect(idempotencyKeys.first, isNotNull);
      expect(idempotencyKeys[1], idempotencyKeys.first);
      expect(result['id'], 'medication-1');
    },
  );

  test('semantic conflict is not retried', () async {
    var requestCount = 0;
    final api = LifeMateApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'access-token',
      httpClient: MockClient((request) async {
        requestCount += 1;
        return http.Response(
          jsonEncode({
            'code': 'stale_dose_occurrence',
            'detail': 'Refresh and try again.',
          }),
          409,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await expectLater(
      api.reportDose(
        occurrenceId: 'dose-1',
        clientRequestId: '22222222-2222-4222-8222-222222222222',
        version: 1,
        status: 'taken',
        occurredAtUtc: DateTime.utc(2026, 7, 30, 12),
      ),
      throwsA(
        isA<LifeMateApiException>().having(
          (error) => error.code,
          'code',
          'stale_dose_occurrence',
        ),
      ),
    );
    expect(requestCount, 1);
  });
  test('home snapshot uses one range-scoped authenticated request', () async {
    late http.Request observed;
    final api = LifeMateApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'access-token',
      httpClient: MockClient((request) async {
        observed = request;
        return http.Response(
          jsonEncode({
            'currentUser': {
              'profile': {'displayName': 'Test'},
            },
            'treatmentPlans': [],
            'doseOccurrences': [],
            'careEvents': [],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final result = await api.getHomeSnapshot(
      fromDate: DateTime(2026, 8, 6),
      toDate: DateTime(2026, 8, 13),
    );

    expect(observed.url.path, '/api/v1/home-snapshot');
    expect(observed.url.queryParameters['fromDate'], '2026-08-06');
    expect(observed.url.queryParameters['toDate'], '2026-08-13');
    expect(result['doseOccurrences'], isEmpty);
  });
}
