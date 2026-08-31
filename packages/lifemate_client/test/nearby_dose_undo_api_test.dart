import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test('undo posts confirmed mutation with idempotency key', () async {
    late http.Request captured;
    final api = LifeMateNearbyDoseUndoApi(
      baseUri: Uri.parse('https://example.test'),
      accessToken: () => 'token',
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'proposalId': '11111111-1111-1111-1111-111111111111',
            'status': 'undone',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final result = await api.undo('11111111-1111-1111-1111-111111111111');
    expect(captured.method, 'POST');
    expect(
      captured.url.path,
      '/api/v1/medication-schedule-optimizations/11111111-1111-1111-1111-111111111111/undo',
    );
    expect(captured.headers['idempotency-key'], isNotEmpty);
    expect(jsonDecode(captured.body), {'confirmed': true});
    expect(result.status, 'undone');
    expect(result.alreadyUndone, isFalse);
    api.close();
  });

  test('stale undo remains a typed 409 and never falls through', () async {
    final api = LifeMateNearbyDoseUndoApi(
      baseUri: Uri.parse('https://example.test'),
      accessToken: () => 'token',
      httpClient: MockClient((request) async => http.Response(
            jsonEncode({
              'code': 'optimization_undo_stale',
              'detail': 'Schedule changed after apply.',
            }),
            409,
            headers: {'content-type': 'application/json'},
          )),
    );

    await expectLater(
      api.undo('11111111-1111-1111-1111-111111111111'),
      throwsA(
        isA<LifeMateApiException>()
            .having((error) => error.statusCode, 'statusCode', 409)
            .having(
              (error) => error.code,
              'code',
              'optimization_undo_stale',
            ),
      ),
    );
    api.close();
  });

  test('missing session fails closed without network', () async {
    var called = false;
    final api = LifeMateNearbyDoseUndoApi(
      baseUri: Uri.parse('https://example.test'),
      accessToken: () => null,
      httpClient: MockClient((_) async {
        called = true;
        return http.Response('{}', 200);
      }),
    );

    await expectLater(
      api.undo('11111111-1111-1111-1111-111111111111'),
      throwsA(
        isA<LifeMateApiException>().having(
          (error) => error.code,
          'code',
          'session_missing',
        ),
      ),
    );
    expect(called, isFalse);
    api.close();
  });
}
