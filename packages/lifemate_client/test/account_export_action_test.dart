import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test('account export uses authenticated self endpoint only', () async {
    late http.Request observed;
    final api = LifeMateAccountExportApi(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'access-token',
      httpClient: MockClient((request) async {
        observed = request;
        final payload = jsonEncode({
          'exportVersion': 1,
          'generatedAtUtc': '2026-08-11T19:30:00Z',
          'dataSubject': {'personId': 'person-a'},
          'account': {'status': 'Active'},
          'profile': {'display_name': 'سارا'},
          'treatment': {'medications': []},
          'health': {'observations': []},
          'womenHealth': {'profile': null, 'episodes': [], 'dailyLogs': []},
          'care': {'relationships': []},
          'privacy': {'consentRecords': []},
        });
        return http.Response.bytes(
          utf8.encode(payload),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final exported = await api.exportMyData();

    expect(observed.method, 'GET');
    expect(observed.url.path, '/api/v1/account/export');
    expect(observed.headers['authorization'], 'Bearer access-token');
    expect(exported['exportVersion'], 1);
  });

  test('account export refuses to call API without a session', () async {
    var calls = 0;
    final api = LifeMateAccountExportApi(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => null,
      httpClient: MockClient((request) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );

    await expectLater(
      api.exportMyData(),
      throwsA(
        isA<LifeMateApiException>().having(
          (value) => value.code,
          'code',
          'session_missing',
        ),
      ),
    );
    expect(calls, 0);
  });
}
