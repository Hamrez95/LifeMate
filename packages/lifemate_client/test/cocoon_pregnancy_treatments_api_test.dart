import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate_client/src/cocoon_pregnancy_treatments_api.dart';
import 'package:lifemate_client/src/lifemate_api_client.dart';

void main() {
  Map<String, dynamic> contextPayload() => {
    'contractVersion': 1,
    'episodeId': '33333333-3333-4333-8333-333333333333',
    'fromDate': '2026-09-14',
    'toDate': '2026-09-20',
    'treatmentPlans': [
      {
        'id': '11111111-1111-4111-8111-111111111111',
        'status': 'Active',
        'doseText': 'canonical dose',
      },
    ],
    'doseOccurrences': [
      {
        'id': '22222222-2222-4222-8222-222222222222',
        'treatmentPlanId': '11111111-1111-4111-8111-111111111111',
      },
    ],
    'mutationAuthority': 'canonical_treatment_api',
  };

  test('reads owner-authorized canonical treatment context', () async {
    late http.Request captured;
    final api = CocoonPregnancyTreatmentsApiClient(
      baseUri: Uri.parse('https://example.test'),
      accessToken: () => 'token',
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(jsonEncode(contextPayload()), 200);
      }),
    );

    final result = await api.list(
      fromDate: DateTime(2026, 9, 14),
      toDate: DateTime(2026, 9, 20),
    );

    expect(captured.method, 'GET');
    expect(captured.url.path, '/api/v1/cocoon/pregnancy/treatments');
    expect(captured.url.queryParameters['fromDate'], '2026-09-14');
    expect(captured.url.queryParameters['toDate'], '2026-09-20');
    expect(captured.headers.containsKey('Idempotency-Key'), isFalse);
    expect(result.treatmentPlans.single['status'], 'Active');
    expect(result.doseOccurrences, hasLength(1));
    expect(result.mutationAuthority, 'canonical_treatment_api');
    api.close();
  });

  test('rejects a response that redirects mutation authority away from shared API', () async {
    final payload = contextPayload()..['mutationAuthority'] = 'cocoon_private_store';
    final api = CocoonPregnancyTreatmentsApiClient(
      baseUri: Uri.parse('https://example.test'),
      accessToken: () => 'token',
      httpClient: MockClient((_) async => http.Response(jsonEncode(payload), 200)),
    );

    await expectLater(
      api.list(
        fromDate: DateTime(2026, 9, 14),
        toDate: DateTime(2026, 9, 20),
      ),
      throwsFormatException,
    );
    api.close();
  });

  test('partner without explicit medication scope fails closed', () async {
    final api = CocoonPregnancyTreatmentsApiClient(
      baseUri: Uri.parse('https://example.test'),
      accessToken: () => 'token',
      httpClient: MockClient((_) async => http.Response(
        jsonEncode({
          'code': 'pregnancy_scope_denied',
          'detail': 'Medication access is not granted.',
        }),
        403,
      )),
    );

    await expectLater(
      api.list(
        fromDate: DateTime(2026, 9, 14),
        toDate: DateTime(2026, 9, 20),
      ),
      throwsA(
        isA<LifeMateApiException>()
            .having((error) => error.statusCode, 'statusCode', 403)
            .having((error) => error.code, 'code', 'pregnancy_scope_denied'),
      ),
    );
    api.close();
  });

  test('empty canonical treatment state remains a valid empty projection', () async {
    final payload = contextPayload()
      ..['treatmentPlans'] = <Map<String, dynamic>>[]
      ..['doseOccurrences'] = <Map<String, dynamic>>[];
    final api = CocoonPregnancyTreatmentsApiClient(
      baseUri: Uri.parse('https://example.test'),
      accessToken: () => 'token',
      httpClient: MockClient((_) async => http.Response(jsonEncode(payload), 200)),
    );

    final result = await api.list(
      fromDate: DateTime(2026, 9, 14),
      toDate: DateTime(2026, 9, 20),
    );
    expect(result.treatmentPlans, isEmpty);
    expect(result.doseOccurrences, isEmpty);
    api.close();
  });

  test('missing session fails before treatment network access', () async {
    var called = false;
    final api = CocoonPregnancyTreatmentsApiClient(
      baseUri: Uri.parse('https://example.test'),
      accessToken: () => null,
      httpClient: MockClient((_) async {
        called = true;
        return http.Response('{}', 200);
      }),
    );

    await expectLater(
      api.list(
        fromDate: DateTime(2026, 9, 14),
        toDate: DateTime(2026, 9, 20),
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
