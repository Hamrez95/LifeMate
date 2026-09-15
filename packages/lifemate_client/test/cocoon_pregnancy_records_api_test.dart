import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate_client/src/cocoon_pregnancy_records_api.dart';
import 'package:lifemate_client/src/lifemate_api_client.dart';

void main() {
  Map<String, dynamic> pagePayload({String? nextCursor = 'next-1'}) => {
    'contractVersion': 1,
    'episodeId': '33333333-3333-4333-8333-333333333333',
    'fromDate': '2026-09-01',
    'toDate': '2026-09-14',
    'categories': ['measurements', 'appointments'],
    'items': [
      {
        'id': 'health_observation:11111111-1111-4111-8111-111111111111',
        'sourceKind': 'health_observation',
        'sourceId': '11111111-1111-4111-8111-111111111111',
        'category': 'measurements',
        'occurredAtUtc': '2026-09-14T09:00:00.000Z',
        'localDate': '2026-09-14',
        'type': 'weight',
        'summary': {'observationType': 'weight'},
        'deepLink': '/health/observations/11111111-1111-4111-8111-111111111111',
        'sourceVersion': 2,
      },
    ],
    'nextCursor': nextCursor,
    'sourceOfTruth': 'composed_canonical_domains',
  };

  test('requests bounded filtered records and parses canonical provenance', () async {
    late http.Request captured;
    final api = CocoonPregnancyRecordsApiClient(
      baseUri: Uri.parse('https://example.test'),
      accessToken: () => 'token',
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(jsonEncode(pagePayload()), 200);
      }),
    );

    final result = await api.list(
      fromDate: DateTime(2026, 9, 1),
      toDate: DateTime(2026, 9, 14),
      categories: {
        CocoonPregnancyRecordCategory.measurements,
        CocoonPregnancyRecordCategory.appointments,
      },
      limit: 25,
    );

    expect(captured.method, 'GET');
    expect(captured.url.path, '/api/v1/cocoon/pregnancy/records');
    expect(captured.url.queryParameters['fromDate'], '2026-09-01');
    expect(captured.url.queryParameters['toDate'], '2026-09-14');
    expect(captured.url.queryParameters['limit'], '25');
    expect(
      captured.url.queryParameters['categories']!.split(',').toSet(),
      {'measurements', 'appointments'},
    );
    expect(result.items.single.sourceKind, 'health_observation');
    expect(result.items.single.sourceVersion, 2);
    expect(result.nextCursor, 'next-1');
    api.close();
  });

  test('forwards opaque cursor without client-side reconstruction', () async {
    late http.Request captured;
    final api = CocoonPregnancyRecordsApiClient(
      baseUri: Uri.parse('https://example.test'),
      accessToken: () => 'token',
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(jsonEncode(pagePayload(nextCursor: null)), 200);
      }),
    );

    final result = await api.list(
      fromDate: DateTime(2026, 9, 1),
      toDate: DateTime(2026, 9, 14),
      cursor: 'opaque-server-cursor',
    );

    expect(captured.url.queryParameters['cursor'], 'opaque-server-cursor');
    expect(result.nextCursor, isNull);
    api.close();
  });

  test('rejects a response that is not composed from canonical domains', () async {
    final payload = pagePayload()..['sourceOfTruth'] = 'timeline_copy';
    final api = CocoonPregnancyRecordsApiClient(
      baseUri: Uri.parse('https://example.test'),
      accessToken: () => 'token',
      httpClient: MockClient((_) async => http.Response(jsonEncode(payload), 200)),
    );

    await expectLater(
      api.list(
        fromDate: DateTime(2026, 9, 1),
        toDate: DateTime(2026, 9, 14),
      ),
      throwsFormatException,
    );
    api.close();
  });

  test('authorization-shaped record denial fails closed', () async {
    final api = CocoonPregnancyRecordsApiClient(
      baseUri: Uri.parse('https://example.test'),
      accessToken: () => 'token',
      httpClient: MockClient((_) async => http.Response(
        jsonEncode({
          'code': 'pregnancy_scope_denied',
          'detail': 'Pregnancy summary access is not granted.',
        }),
        403,
      )),
    );

    await expectLater(
      api.list(
        fromDate: DateTime(2026, 9, 1),
        toDate: DateTime(2026, 9, 14),
      ),
      throwsA(
        isA<LifeMateApiException>()
            .having((error) => error.statusCode, 'statusCode', 403)
            .having((error) => error.code, 'code', 'pregnancy_scope_denied'),
      ),
    );
    api.close();
  });

  test('invalid local page size is rejected before network access', () async {
    var called = false;
    final api = CocoonPregnancyRecordsApiClient(
      baseUri: Uri.parse('https://example.test'),
      accessToken: () => 'token',
      httpClient: MockClient((_) async {
        called = true;
        return http.Response('{}', 200);
      }),
    );

    await expectLater(
      api.list(
        fromDate: DateTime(2026, 9, 1),
        toDate: DateTime(2026, 9, 14),
        limit: 101,
      ),
      throwsArgumentError,
    );
    expect(called, isFalse);
    api.close();
  });

  test('missing session fails before records network access', () async {
    var called = false;
    final api = CocoonPregnancyRecordsApiClient(
      baseUri: Uri.parse('https://example.test'),
      accessToken: () => null,
      httpClient: MockClient((_) async {
        called = true;
        return http.Response('{}', 200);
      }),
    );

    await expectLater(
      api.list(
        fromDate: DateTime(2026, 9, 1),
        toDate: DateTime(2026, 9, 14),
      ),
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
