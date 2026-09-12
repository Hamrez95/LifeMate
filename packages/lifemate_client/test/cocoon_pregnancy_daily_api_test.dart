import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate_client/src/cocoon_pregnancy_daily_api.dart';
import 'package:lifemate_client/src/lifemate_api_client.dart';

void main() {
  const requestId = '123e4567-e89b-42d3-a456-426614174000';
  final catalog = CocoonApprovedSymptomCatalog(
    version: '2026-09-12.1',
    codes: const ['approved-nausea', 'approved-headache'],
  );

  Map<String, dynamic> capture({
    String id = 'capture-1',
    String? symptomCode,
    String? intensity,
  }) => {
    'id': id,
    'episodeId': 'episode-1',
    'observedAtUtc': '2026-09-12T08:00:00.000Z',
    'localDate': '2026-09-12',
    'timeZone': 'Asia/Tehran',
    'symptomCode': symptomCode,
    'intensity': intensity,
    'version': 1,
  };

  test('daily list uses the canonical bounded read route', () async {
    late http.Request captured;
    final api = CocoonPregnancyDailyApiClient(
      baseUri: Uri.parse('https://example.test'),
      accessToken: () => 'token',
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'contractVersion': 1,
            'episodeId': 'episode-1',
            'checkIns': [capture(id: 'check-in-1')],
            'symptoms': [
              capture(
                id: 'symptom-1',
                symptomCode: 'approved-nausea',
                intensity: 'moderate',
              ),
            ],
            'moods': [capture(id: 'mood-1')],
          }),
          200,
        );
      }),
    );

    final result = await api.list(
      fromDate: DateTime(2026, 9, 1),
      toDate: DateTime(2026, 9, 12),
    );

    expect(captured.method, 'GET');
    expect(captured.url.path, '/api/v1/cocoon/pregnancy/daily-captures');
    expect(captured.url.queryParameters['fromDate'], '2026-09-01');
    expect(captured.url.queryParameters['toDate'], '2026-09-12');
    expect(result.symptoms.single.symptomCode, 'approved-nausea');
    api.close();
  });

  test('symptom submit preserves approved code, severity and stable request id', () async {
    late http.Request captured;
    final api = CocoonPregnancyDailyApiClient(
      baseUri: Uri.parse('https://example.test'),
      accessToken: () => 'token',
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'contractVersion': 1,
            'symptom': capture(
              symptomCode: 'approved-nausea',
              intensity: 'moderate',
            ),
          }),
          201,
        );
      }),
    );

    final result = await api.createSymptom(
      approvedCatalog: catalog,
      symptomCode: 'approved-nausea',
      intensity: CocoonPregnancySymptomIntensity.moderate,
      clientRequestId: requestId,
      observedAtUtc: DateTime.utc(2026, 9, 12, 8),
      localDate: '2026-09-12',
      timeZone: 'Asia/Tehran',
      note: 'private note',
    );

    expect(captured.url.path, '/api/v1/cocoon/pregnancy/symptoms');
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['clientRequestId'], requestId);
    expect(body['symptomCode'], 'approved-nausea');
    expect(body['intensity'], 'moderate');
    expect(body['note'], 'private note');
    expect(result.symptomCode, 'approved-nausea');
    api.close();
  });

  test('symptom outside approved injected catalog is rejected before network', () async {
    var called = false;
    final api = CocoonPregnancyDailyApiClient(
      baseUri: Uri.parse('https://example.test'),
      accessToken: () => 'token',
      httpClient: MockClient((_) async {
        called = true;
        return http.Response('{}', 201);
      }),
    );

    await expectLater(
      api.createSymptom(
        approvedCatalog: catalog,
        symptomCode: 'invented-symptom',
        intensity: CocoonPregnancySymptomIntensity.strong,
        clientRequestId: requestId,
        observedAtUtc: DateTime.utc(2026, 9, 12, 8),
        localDate: '2026-09-12',
        timeZone: 'Asia/Tehran',
      ),
      throwsArgumentError,
    );
    expect(called, isFalse);
    api.close();
  });

  test('revoked pregnancy access fails closed', () async {
    final api = CocoonPregnancyDailyApiClient(
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
        fromDate: DateTime(2026, 9, 12),
        toDate: DateTime(2026, 9, 12),
      ),
      throwsA(
        isA<LifeMateApiException>()
            .having((error) => error.statusCode, 'statusCode', 403)
            .having((error) => error.code, 'code', 'pregnancy_scope_denied'),
      ),
    );
    api.close();
  });

  test('missing session fails before daily capture network access', () async {
    var called = false;
    final api = CocoonPregnancyDailyApiClient(
      baseUri: Uri.parse('https://example.test'),
      accessToken: () => null,
      httpClient: MockClient((_) async {
        called = true;
        return http.Response('{}', 200);
      }),
    );

    await expectLater(
      api.list(
        fromDate: DateTime(2026, 9, 12),
        toDate: DateTime(2026, 9, 12),
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
