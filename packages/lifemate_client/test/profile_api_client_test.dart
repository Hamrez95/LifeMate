import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test('profile read uses authenticated owner route', () async {
    late http.Request observed;
    final api = LifeMateApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'access-token',
      httpClient: MockClient((request) async {
        observed = request;
        return http.Response(
          jsonEncode({
            'id': 'profile-1',
            'userId': 'user-1',
            'displayName': 'ریحانه',
            'email': 'owner@example.test',
            'locale': 'fa',
            'timeZone': 'Asia/Tehran',
            'version': 3,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final profile = await api.getCurrentProfile();

    expect(observed.method, 'GET');
    expect(observed.url.path, '/api/v1/me/profile');
    expect(observed.headers['authorization'], 'Bearer access-token');
    expect(profile['version'], 3);
  });

  test('profile edit sends a normalized optimistic-concurrency payload',
      () async {
    late http.Request observed;
    final api = LifeMateApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'access-token',
      httpClient: MockClient((request) async {
        observed = request;
        return http.Response(
          jsonEncode({
            'id': 'profile-1',
            'displayName': 'ریحانه شکیبا',
            'phoneNumber': '+989121234567',
            'locale': 'fa',
            'timeZone': 'Asia/Tehran',
            'version': 4,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final profile = await api.updateCurrentProfile(
      version: 3,
      displayName: '  ریحانه شکیبا  ',
      phoneNumber: ' +989121234567 ',
      locale: ' fa ',
      timeZone: ' Asia/Tehran ',
    );

    expect(observed.method, 'PATCH');
    expect(observed.url.path, '/api/v1/me/profile');
    final payload = jsonDecode(observed.body) as Map<String, dynamic>;
    expect(payload, {
      'version': 3,
      'displayName': 'ریحانه شکیبا',
      'phoneNumber': '+989121234567',
      'locale': 'fa',
      'timeZone': 'Asia/Tehran',
    });
    expect(profile['version'], 4);
  });

  test('profile edit is not retried when the response is lost', () async {
    var requests = 0;
    final api = LifeMateApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'access-token',
      httpClient: MockClient((request) async {
        requests += 1;
        throw http.ClientException('response lost', request.url);
      }),
    );

    await expectLater(
      api.updateCurrentProfile(
        version: 1,
        displayName: 'Owner',
        locale: 'fa',
        timeZone: 'Asia/Tehran',
      ),
      throwsA(
        isA<LifeMateApiException>().having(
          (error) => error.code,
          'code',
          'network_unavailable',
        ),
      ),
    );
    expect(requests, 1);
  });
}
