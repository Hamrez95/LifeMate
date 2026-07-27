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
            {
              'id': 'dose-1',
              'medicationName': 'Metformin',
              'status': 'taken',
            }
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
}
