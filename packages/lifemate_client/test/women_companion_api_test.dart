import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test('daily logs request is authenticated and range scoped', () async {
    late http.Request observed;
    final api = WomenCompanionApi(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'access-token',
      httpClient: MockClient((request) async {
        observed = request;
        return http.Response(
          jsonEncode([
            {
              'id': 'daily-1',
              'loggedOn': '2026-08-05',
              'mood': 'good',
              'energyLevel': 4,
              'painLevel': 1,
              'symptoms': ['fatigue'],
              'privateNotes': 'owner only',
              'shareSummaryWithCompanion': false,
              'version': 1,
            },
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final result = await api.getDailyLogs(
      fromDate: DateTime(2026, 8, 1),
      toDate: DateTime(2026, 8, 5),
    );

    expect(observed.method, 'GET');
    expect(observed.url.path, '/api/v1/women-calendar/daily-logs');
    expect(observed.url.queryParameters, {
      'fromDate': '2026-08-01',
      'toDate': '2026-08-05',
    });
    expect(observed.headers['authorization'], 'Bearer access-token');
    expect(result.single['privateNotes'], 'owner only');
  });

  test(
    'daily log save sends explicit companion consent and idempotency key',
    () async {
      late http.Request observed;
      final api = WomenCompanionApi(
        baseUri: Uri.parse('https://api.example.test'),
        accessToken: () => 'access-token',
        httpClient: MockClient((request) async {
          observed = request;
          return http.Response(
            jsonEncode({
              'id': 'daily-1',
              'loggedOn': '2026-08-05',
              'mood': 'low',
              'energyLevel': 2,
              'painLevel': 3,
              'symptoms': ['cramps', 'fatigue'],
              'privateNotes': 'فقط برای خودم',
              'shareSummaryWithCompanion': true,
              'version': 2,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final result = await api.saveDailyLog(
        version: 1,
        loggedOn: DateTime(2026, 8, 5),
        mood: ' LOW ',
        energyLevel: 2,
        painLevel: 3,
        symptoms: const [' Cramps ', 'Fatigue'],
        privateNotes: '  فقط برای خودم  ',
        shareSummaryWithCompanion: true,
      );

      expect(observed.method, 'PUT');
      expect(observed.url.path, '/api/v1/women-calendar/daily-logs');
      expect(observed.headers['authorization'], 'Bearer access-token');
      expect(observed.headers['idempotency-key'], isNotEmpty);
      expect(jsonDecode(observed.body), {
        'version': 1,
        'loggedOn': '2026-08-05',
        'mood': 'low',
        'energyLevel': 2,
        'painLevel': 3,
        'symptoms': ['cramps', 'fatigue'],
        'privateNotes': 'فقط برای خودم',
        'shareSummaryWithCompanion': true,
      });
      expect(result['version'], 2);
    },
  );

  test('guidance impression sends identifiers only', () async {
    late http.Request observed;
    final api = WomenCompanionApi(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'access-token',
      httpClient: MockClient((request) async {
        observed = request;
        return http.Response(
          jsonEncode({
            'id': 'history-1',
            'guidanceId': 'energy.give_space',
            'contentVersion': 'companion-care-v1',
            'category': 'energy',
            'shownAtUtc': '2026-08-26T16:00:00.000Z',
          }),
          201,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await api.recordGuidanceImpression(
      patientUserId: 'patient-id',
      guidanceId: ' energy.give_space ',
      contentVersion: ' companion-care-v1 ',
      category: ' ENERGY ',
    );

    expect(observed.method, 'POST');
    expect(
      observed.url.path,
      '/api/v1/care/patients/patient-id/women-calendar/guidance-impressions',
    );
    expect(observed.headers['authorization'], 'Bearer access-token');
    expect(observed.headers['idempotency-key'], isNotEmpty);
    expect(jsonDecode(observed.body), {
      'guidanceId': 'energy.give_space',
      'contentVersion': 'companion-care-v1',
      'category': 'energy',
    });
    expect(observed.body, isNot(contains('mood')));
    expect(observed.body, isNot(contains('privateNotes')));
    expect(observed.body, isNot(contains('symptoms')));
  });

  test('daily log lost-response retry reuses one idempotency key', () async {
    var attempts = 0;
    final idempotencyKeys = <String?>[];
    final api = WomenCompanionApi(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'access-token',
      httpClient: MockClient((request) async {
        attempts += 1;
        idempotencyKeys.add(request.headers['idempotency-key']);
        if (attempts == 1) {
          throw http.ClientException('response lost', request.url);
        }
        return http.Response(
          jsonEncode({
            'id': 'daily-retry',
            'loggedOn': '2026-08-05',
            'mood': 'good',
            'energyLevel': 4,
            'painLevel': 0,
            'symptoms': ['no_symptom'],
            'privateNotes': null,
            'shareSummaryWithCompanion': false,
            'version': 2,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final result = await api.saveDailyLog(
      version: 1,
      loggedOn: DateTime(2026, 8, 5),
      mood: 'good',
      energyLevel: 4,
      painLevel: 0,
      symptoms: const ['no_symptom'],
      shareSummaryWithCompanion: false,
    );

    expect(attempts, 2);
    expect(idempotencyKeys.first, isNotNull);
    expect(idempotencyKeys[1], idempotencyKeys.first);
    expect(result['id'], 'daily-retry');
  });

  test('stale daily log response preserves API error code', () async {
    final api = WomenCompanionApi(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'access-token',
      httpClient: MockClient(
        (request) async => http.Response(
          jsonEncode({
            'code': 'stale_women_calendar_daily_log',
            'message': 'Daily log changed.',
          }),
          409,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );

    await expectLater(
      api.saveDailyLog(
        version: 1,
        loggedOn: DateTime(2026, 8, 5),
        mood: 'good',
        energyLevel: 3,
        painLevel: 0,
        symptoms: const ['no_symptom'],
        shareSummaryWithCompanion: false,
      ),
      throwsA(
        isA<LifeMateApiException>()
            .having((error) => error.statusCode, 'statusCode', 409)
            .having(
              (error) => error.code,
              'code',
              'stale_women_calendar_daily_log',
            ),
      ),
    );
  });

  test(
    'daily log save preserves nested Supabase Edge Function base path',
    () async {
      late http.Request observed;
      final api = WomenCompanionApi(
        baseUri: Uri.parse(
          'https://project.supabase.co/functions/v1/lifemate-api',
        ),
        accessToken: () => 'access-token',
        httpClient: MockClient((request) async {
          observed = request;
          return http.Response(
            jsonEncode({
              'id': 'daily-1',
              'loggedOn': '2026-08-08',
              'mood': 'good',
              'energyLevel': 5,
              'painLevel': 3,
              'symptoms': ['headache'],
              'privateNotes': null,
              'shareSummaryWithCompanion': false,
              'version': 2,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await api.saveDailyLog(
        version: 1,
        loggedOn: DateTime(2026, 8, 8),
        mood: 'good',
        energyLevel: 5,
        painLevel: 3,
        symptoms: const ['headache'],
        shareSummaryWithCompanion: false,
      );

      expect(
        observed.url.path,
        '/functions/v1/lifemate-api/api/v1/women-calendar/daily-logs',
      );
    },
  );
}
