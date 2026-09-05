import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test('care-event pull maps upserts and tombstones without Person ids', () async {
    late http.Request captured;
    final client = LifeMateIncrementalProjectionApi(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'token-a',
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'nextCursor': 'v1.next',
            'hasMore': false,
            'changes': [
              {
                'recordKey': 'event-a',
                'deleted': false,
                'sourceRevision': '3',
                'sourceUpdatedAtUtc': '2026-09-05T01:02:03.000Z',
                'payload': {
                  'id': 'event-a',
                  'title': 'opaque test event',
                  'status': 'scheduled',
                },
              },
              {
                'recordKey': 'event-b',
                'deleted': true,
                'sourceRevision': '4',
                'sourceUpdatedAtUtc': '2026-09-05T01:03:03.000Z',
                'payload': null,
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final page = await client.pullCareEvents(cursor: 'v1.previous', limit: 50);

    expect(captured.method, 'GET');
    expect(captured.url.path, '/api/v1/sync/care-events');
    expect(captured.url.queryParameters['cursor'], 'v1.previous');
    expect(captured.url.queryParameters['limit'], '50');
    expect(captured.headers['Authorization'], 'Bearer token-a');
    expect(page.nextCursor, 'v1.next');
    expect(page.hasMore, isFalse);
    expect(page.changes, hasLength(2));
    expect(page.changes.first.deleted, isFalse);
    expect(page.changes.first.payload?['title'], 'opaque test event');
    expect(page.changes.last.deleted, isTrue);
  });

  test('missing token fails closed before network access', () async {
    var called = false;
    final client = LifeMateIncrementalProjectionApi(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => null,
      httpClient: MockClient((request) async {
        called = true;
        return http.Response('{}', 200);
      }),
    );

    await expectLater(
      client.pullCareEvents(),
      throwsA(
        isA<LifeMateApiException>()
            .having((error) => error.statusCode, 'statusCode', 401)
            .having((error) => error.code, 'code', 'authorization_missing'),
      ),
    );
    expect(called, isFalse);
  });

  test('invalid server payload is rejected instead of partially applying', () async {
    final client = LifeMateIncrementalProjectionApi(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'token-a',
      httpClient: MockClient(
        (request) async => http.Response(
          jsonEncode({
            'nextCursor': 'v1.next',
            'changes': [
              {
                'recordKey': 'event-a',
                'deleted': false,
                'payload': null,
              },
            ],
          }),
          200,
        ),
      ),
    );

    await expectLater(
      client.pullCareEvents(),
      throwsA(
        isA<LifeMateApiException>().having(
          (error) => error.code,
          'code',
          'invalid_api_response',
        ),
      ),
    );
  });
}
