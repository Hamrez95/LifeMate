import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test('health observations list is authenticated and date scoped', () async {
    late http.Request observed;
    final api = LifeMateHealthApi(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'access-token',
      httpClient: MockClient((request) async {
        observed = request;
        return http.Response(
          jsonEncode([
            {
              'id': 'obs-1',
              'personId': 'person-1',
              'observationType': 'weight',
              'valuePrimary': 78.4,
              'valueSecondary': null,
              'unitPrimary': 'kg',
              'unitSecondary': null,
              'note': null,
              'observedAtUtc': '2026-08-10T08:00:00Z',
              'observedLocalDate': '2026-08-10',
              'timeZone': 'Asia/Tehran',
              'sourceCategory': 'FirstPartyUserInput',
              'sourceProvider': 'wellmate',
              'sourceApplicationCode': 'wellmate',
              'version': 1,
            },
          ]),
          200,
        );
      }),
    );

    final values = await api.listObservations(
      fromDate: DateTime(2026, 8, 1),
      toDate: DateTime(2026, 8, 10),
    );

    expect(observed.method, 'GET');
    expect(observed.headers['authorization'], 'Bearer access-token');
    expect(observed.url.path, '/api/v1/health/observations');
    expect(observed.url.queryParameters['fromDate'], '2026-08-01');
    expect(observed.url.queryParameters['toDate'], '2026-08-10');
    expect(values.single.valuePrimary, 78.4);
    expect(values.single.sourceApplicationCode, 'wellmate');
  });

  test('health observation creation sends cross-app provenance', () async {
    late http.Request observed;
    final api = LifeMateHealthApi(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'access-token',
      applicationCode: 'fitmate',
      httpClient: MockClient((request) async {
        observed = request;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'id': 'obs-2',
            'personId': 'person-1',
            'observationType': body['observationType'],
            'valuePrimary': body['valuePrimary'],
            'valueSecondary': body['valueSecondary'],
            'unitPrimary': 'mmHg',
            'unitSecondary': 'mmHg',
            'note': body['note'],
            'observedAtUtc': body['observedAtUtc'],
            'observedLocalDate': body['observedLocalDate'],
            'timeZone': body['timeZone'],
            'sourceCategory': 'FirstPartyUserInput',
            'sourceProvider': 'fitmate',
            'sourceApplicationCode': body['sourceApplicationCode'],
            'version': 1,
          }),
          201,
        );
      }),
    );

    await api.createObservation(
      observationType: 'blood_pressure',
      valuePrimary: 118,
      valueSecondary: 76,
      observedAtUtc: DateTime.utc(2026, 8, 10, 8),
      observedLocalDate: DateTime(2026, 8, 10, 12),
      timeZone: 'Asia/Tehran',
      clientRequestId: '123e4567-e89b-42d3-a456-426614174000',
    );

    final body = jsonDecode(observed.body) as Map<String, dynamic>;
    expect(observed.method, 'POST');
    expect(body['clientRequestId'], '123e4567-e89b-42d3-a456-426614174000');
    expect(
      observed.headers['idempotency-key'],
      '123e4567-e89b-42d3-a456-426614174000',
    );
    expect(body['sourceApplicationCode'], 'fitmate');
    expect(body['observationType'], 'blood_pressure');
    expect(body['valuePrimary'], 118);
    expect(body['valueSecondary'], 76);
    expect(body['observedLocalDate'], '2026-08-10');
  });

  test(
    'entered wall clock is converted using the declared profile zone',
    () async {
      late Map<String, dynamic> sent;
      final api = LifeMateHealthApi(
        baseUri: Uri.parse('https://api.example.test'),
        accessToken: () => 'access-token',
        httpClient: MockClient((request) async {
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'id': 'obs-time',
              'personId': 'person-1',
              'observationType': sent['observationType'],
              'valuePrimary': sent['valuePrimary'],
              'valueSecondary': null,
              'unitPrimary': 'kg',
              'unitSecondary': null,
              'note': null,
              'observedAtUtc': sent['observedAtUtc'],
              'observedLocalDate': sent['observedLocalDate'],
              'timeZone': sent['timeZone'],
              'sourceCategory': 'FirstPartyUserInput',
              'sourceProvider': 'wellmate',
              'sourceApplicationCode': 'wellmate',
              'version': 1,
            }),
            201,
          );
        }),
      );

      await api.createObservation(
        observationType: 'weight',
        valuePrimary: 78,
        observedAtUtc: DateTime.utc(2026, 8, 10, 12),
        observedLocalDate: DateTime(2026, 8, 10, 12),
        timeZone: 'Asia/Tehran',
        clientRequestId: '123e4567-e89b-42d3-a456-426614174001',
      );

      // Tehran is UTC+03:30 in August 2026. The device zone must not affect the
      // instant represented by the user's entered 12:00 wall clock.
      expect(sent['observedAtUtc'], '2026-08-10T08:30:00.000Z');
    },
  );

  test('automatic client request id survives a lost-response retry', () async {
    final requestIds = <String>[];
    final idempotencyKeys = <String?>[];
    var attempts = 0;
    final api = LifeMateHealthApi(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'access-token',
      httpClient: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        requestIds.add(body['clientRequestId'].toString());
        idempotencyKeys.add(request.headers['idempotency-key']);
        attempts++;
        if (attempts == 1) {
          throw http.ClientException('response lost');
        }
        return http.Response(
          jsonEncode({
            'id': 'obs-retry',
            'personId': 'person-1',
            'observationType': body['observationType'],
            'valuePrimary': body['valuePrimary'],
            'valueSecondary': null,
            'unitPrimary': 'kg',
            'unitSecondary': null,
            'note': null,
            'observedAtUtc': body['observedAtUtc'],
            'observedLocalDate': body['observedLocalDate'],
            'timeZone': body['timeZone'],
            'sourceCategory': 'FirstPartyUserInput',
            'sourceProvider': 'wellmate',
            'sourceApplicationCode': 'wellmate',
            'version': 1,
          }),
          201,
        );
      }),
    );

    await api.createObservation(
      observationType: 'weight',
      valuePrimary: 78,
      observedAtUtc: DateTime.utc(2026, 8, 10, 8),
      observedLocalDate: DateTime(2026, 8, 10, 11, 30),
      timeZone: 'Asia/Tehran',
    );

    expect(requestIds, hasLength(2));
    expect(requestIds[1], requestIds[0]);
    expect(idempotencyKeys[0], requestIds[0]);
    expect(idempotencyKeys[1], requestIds[0]);
  });

  test('health observation delete remains behind the API boundary', () async {
    late http.Request observed;
    final api = LifeMateHealthApi(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'access-token',
      httpClient: MockClient((request) async {
        observed = request;
        return http.Response('', 204);
      }),
    );

    await api.deleteObservation(observationId: 'obs-3');

    expect(observed.method, 'DELETE');
    expect(observed.url.path, '/api/v1/health/observations/obs-3');
    expect(observed.headers['authorization'], 'Bearer access-token');
    expect(observed.headers['idempotency-key'], isNotEmpty);
  });
}
