import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test('registration status preserves required document version and accepted state', () async {
    final api = LifeMateLegalPrivacyApi(
      baseUri: Uri.parse('https://example.test'),
      accessToken: () => 'token',
      httpClient: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/v1/account/registration');
        return http.Response(
          jsonEncode({
            'completed': false,
            'registrationPolicyVersion': null,
            'requiredDocuments': [
              {
                'id': '11111111-1111-4111-8111-111111111111',
                'purpose': 'legal_terms',
                'version': 'v3',
                'title': 'Terms',
                'documentHash': 'sha256:abcdefghijklmnop',
                'contentUri': 'https://example.test/terms',
                'accepted': false,
              },
            ],
          }),
          200,
        );
      }),
    );

    final status = await api.registrationStatus();
    expect(status.completed, isFalse);
    expect(status.requiredDocuments, hasLength(1));
    expect(status.requiredDocuments.single.version, 'v3');
    expect(status.requiredDocuments.single.accepted, isFalse);
    api.close();
  });

  test('legal acceptance sends explicit current document id/hash with idempotency', () async {
    final requests = <http.Request>[];
    var statusCalls = 0;
    final api = LifeMateLegalPrivacyApi(
      baseUri: Uri.parse('https://example.test'),
      accessToken: () => 'token',
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.method == 'POST') {
          return http.Response(jsonEncode({'completed': true}), 200);
        }
        statusCalls += 1;
        return http.Response(
          jsonEncode({
            'completed': true,
            'registrationPolicyVersion': 'legal_terms:v3',
            'requiredDocuments': [],
          }),
          200,
        );
      }),
    );

    const document = LifeMateLegalDocument(
      id: '11111111-1111-4111-8111-111111111111',
      purpose: 'legal_terms',
      version: 'v3',
      title: 'Terms',
      documentHash: 'sha256:abcdefghijklmnop',
      contentUri: 'https://example.test/terms',
      accepted: false,
    );
    final status = await api.acceptCurrentLegalDocuments([document]);

    expect(requests.first.url.path, '/api/v1/account/registration/legal-acceptance');
    expect(requests.first.headers['idempotency-key'], isNotEmpty);
    final body = jsonDecode(requests.first.body) as Map<String, dynamic>;
    final acceptance = (body['acceptances'] as List).single as Map<String, dynamic>;
    expect(acceptance['documentId'], document.id);
    expect(acceptance['documentHash'], document.documentHash);
    expect(status.completed, isTrue);
    expect(statusCalls, 1);
    api.close();
  });

  test('privacy preference PATCH is purpose-scoped and never mutates critical communications', () async {
    late http.Request captured;
    final api = LifeMateLegalPrivacyApi(
      baseUri: Uri.parse('https://example.test'),
      accessToken: () => 'token',
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(jsonEncode({'enabled': false}), 200);
      }),
    );

    await api.setPrivacyPreference(purpose: 'promotional_sms', enabled: false);

    expect(captured.method, 'PATCH');
    expect(captured.url.path, '/api/v1/account/privacy-preferences/promotional_sms');
    expect(captured.headers['idempotency-key'], isNotEmpty);
    expect(jsonDecode(captured.body), {'enabled': false});
    expect(captured.body.contains('transactional'), isFalse);
    expect(captured.body.contains('security'), isFalse);
    expect(captured.body.contains('care'), isFalse);
    api.close();
  });

  test('missing session fails closed before legal/privacy network access', () async {
    var called = false;
    final api = LifeMateLegalPrivacyApi(
      baseUri: Uri.parse('https://example.test'),
      accessToken: () => null,
      httpClient: MockClient((_) async {
        called = true;
        return http.Response('{}', 200);
      }),
    );

    await expectLater(
      api.privacyPreferences(),
      throwsA(isA<LifeMateApiException>().having((e) => e.code, 'code', 'session_missing')),
    );
    expect(called, isFalse);
    api.close();
  });
}
