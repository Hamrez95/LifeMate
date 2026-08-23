import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test('phone care request sends caregiver consent without SMS or token', () async {
    late http.Request observed;
    final api = PhoneCareRequestApi(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'access-token',
      httpClient: MockClient((request) async {
        observed = request;
        return http.Response(
          jsonEncode({
            'id': 'request-1',
            'status': 'pending',
            'contactHint': '+98 ••• •• 5678',
          }),
          201,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final result = await api.create(phone: ' ۰۹۳۵ ۱۲۳ ۵۶۷۸ ');
    final body = jsonDecode(observed.body) as Map<String, dynamic>;

    expect(observed.method, 'POST');
    expect(observed.url.path, '/api/v1/care/requests');
    expect(observed.headers['authorization'], 'Bearer access-token');
    expect(observed.headers['idempotency-key'], isNotEmpty);
    expect(body['contactType'], 'phone');
    expect(body['contact'], '۰۹۳۵ ۱۲۳ ۵۶۷۸');
    expect(body['consentVersion'], 'care-caregiver-request-v1');
    expect(body['confirmConsent'], isTrue);
    expect(body.containsKey('token'), isFalse);
    expect(result['status'], 'pending');
  });

  test('missing session fails before phone leaves the device', () async {
    var requested = false;
    final api = PhoneCareRequestApi(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => null,
      httpClient: MockClient((request) async {
        requested = true;
        return http.Response('{}', 200);
      }),
    );

    await expectLater(
      api.create(phone: '09121234567'),
      throwsA(isA<LifeMateApiException>().having((e) => e.code, 'code', 'session_missing')),
    );
    expect(requested, isFalse);
  });

  test('generic server response does not require target identity', () async {
    final api = PhoneCareRequestApi(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'access-token',
      httpClient: MockClient((request) async => http.Response(
        jsonEncode({'id': 'request-1', 'status': 'pending', 'contactHint': '+98 ••• •• 5678'}),
        201,
        headers: {'content-type': 'application/json'},
      )),
    );

    final result = await api.create(phone: '09121234567');
    expect(result.containsKey('targetAccountId'), isFalse);
    expect(result.containsKey('targetDisplayName'), isFalse);
    expect(result.containsKey('phone'), isFalse);
  });
}
