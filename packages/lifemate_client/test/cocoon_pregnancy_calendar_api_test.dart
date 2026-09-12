import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate_client/src/cocoon_pregnancy_calendar_api.dart';
import 'package:lifemate_client/src/lifemate_api_client.dart';

void main() {
  test('calendar list uses authorized canonical Cocoon route', () async {
    late http.Request captured;
    final api = CocoonPregnancyCalendarApiClient(
      baseUri: Uri.parse('https://example.test'),
      accessToken: () => 'token',
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'contractVersion': 1,
            'episodeId': 'episode-1',
            'fromDate': '2026-09-01',
            'toDate': '2026-09-30',
            'items': [
              {
                'id': 'event-1',
                'seriesId': 'series-1',
                'pregnancyClassification': 'ultrasound',
                'title': 'private canonical event',
              },
            ],
          }),
          200,
        );
      }),
    );

    final page = await api.list(
      fromDate: DateTime(2026, 9, 1),
      toDate: DateTime(2026, 9, 30),
    );

    expect(captured.method, 'GET');
    expect(captured.url.path, '/api/v1/cocoon/pregnancy/calendar');
    expect(captured.url.queryParameters['fromDate'], '2026-09-01');
    expect(captured.url.queryParameters['toDate'], '2026-09-30');
    expect(captured.headers['authorization'], 'Bearer token');
    expect(page.episodeId, 'episode-1');
    expect(page.items.single.id, 'series-1');
    expect(
      page.items.single.classification,
      CocoonPregnancyCalendarClassification.ultrasound,
    );
    api.close();
  });

  test('create requires canonical client request id before network', () async {
    var called = false;
    final api = CocoonPregnancyCalendarApiClient(
      baseUri: Uri.parse('https://example.test'),
      accessToken: () => 'token',
      httpClient: MockClient((_) async {
        called = true;
        return http.Response('{}', 201);
      }),
    );

    expect(
      () => api.createEvent(
        careEvent: const {'title': 'appointment'},
        classification: CocoonPregnancyCalendarClassification.checkup,
      ),
      throwsArgumentError,
    );
    await Future<void>.delayed(Duration.zero);
    expect(called, isFalse);
    api.close();
  });

  test('revoked or unauthorized access fails closed', () async {
    final api = CocoonPregnancyCalendarApiClient(
      baseUri: Uri.parse('https://example.test'),
      accessToken: () => 'token',
      httpClient: MockClient((_) async => http.Response(
        jsonEncode({
          'code': 'pregnancy_scope_denied',
          'detail': 'Pregnancy access was revoked.',
        }),
        403,
      )),
    );

    await expectLater(
      api.list(
        fromDate: DateTime(2026, 9, 1),
        toDate: DateTime(2026, 9, 2),
      ),
      throwsA(
        isA<LifeMateApiException>()
            .having((error) => error.statusCode, 'statusCode', 403)
            .having((error) => error.code, 'code', 'pregnancy_scope_denied'),
      ),
    );
    api.close();
  });

  test('missing session fails before network access', () async {
    var called = false;
    final api = CocoonPregnancyCalendarApiClient(
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
        toDate: DateTime(2026, 9, 2),
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
