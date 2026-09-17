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
        'status': 'active',
        'doseText': 'canonical dose',
        'version': 3,
        'medication': {
          'id': '44444444-4444-4444-8444-444444444444',
          'name': 'Canonical medication',
          'strengthText': 'canonical strength',
        },
      },
    ],
    'doseOccurrences': [
      {
        'id': '22222222-2222-4222-8222-222222222222',
        'treatmentPlanId': '11111111-1111-4111-8111-111111111111',
        'scheduledAtUtc': '2026-09-16T05:30:00.000Z',
        'scheduledLocalDate': '2026-09-16',
        'scheduledLocalTime': '09:00',
        'timeZone': 'Asia/Tehran',
        'status': 'scheduled',
        'version': 7,
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
    expect(result.treatmentPlans.single['status'], 'active');
    expect(result.doseOccurrences, hasLength(1));
    expect(result.mutationAuthority, 'canonical_treatment_api');

    final plan = result.typedTreatmentPlans.single;
    expect(plan.id, '11111111-1111-4111-8111-111111111111');
    expect(plan.medicationId, '44444444-4444-4444-8444-444444444444');
    expect(plan.medicationName, 'Canonical medication');
    expect(plan.doseText, 'canonical dose');
    expect(plan.version, 3);

    final occurrence = result.typedDoseOccurrences.single;
    expect(occurrence.id, '22222222-2222-4222-8222-222222222222');
    expect(occurrence.treatmentPlanId, plan.id);
    expect(occurrence.version, 7);
    expect(occurrence.status, 'scheduled');
    expect(occurrence.scheduledAtUtc, DateTime.utc(2026, 9, 16, 5, 30));
    api.close();
  });

  test(
    'rejects a response that redirects mutation authority away from shared API',
    () async {
      final payload = contextPayload()
        ..['mutationAuthority'] = 'cocoon_private_store';
      final api = CocoonPregnancyTreatmentsApiClient(
        baseUri: Uri.parse('https://example.test'),
        accessToken: () => 'token',
        httpClient: MockClient(
          (_) async => http.Response(jsonEncode(payload), 200),
        ),
      );

      await expectLater(
        api.list(
          fromDate: DateTime(2026, 9, 14),
          toDate: DateTime(2026, 9, 20),
        ),
        throwsFormatException,
      );
      api.close();
    },
  );

  test('rejects occurrence identity that does not belong to an active plan', () async {
    final payload = contextPayload();
    (payload['doseOccurrences'] as List).single['treatmentPlanId'] =
        '99999999-9999-4999-8999-999999999999';
    final api = CocoonPregnancyTreatmentsApiClient(
      baseUri: Uri.parse('https://example.test'),
      accessToken: () => 'token',
      httpClient: MockClient(
        (_) async => http.Response(jsonEncode(payload), 200),
      ),
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

  test('rejects occurrence without canonical version', () async {
    final payload = contextPayload();
    (payload['doseOccurrences'] as List).single.remove('version');
    final api = CocoonPregnancyTreatmentsApiClient(
      baseUri: Uri.parse('https://example.test'),
      accessToken: () => 'token',
      httpClient: MockClient(
        (_) async => http.Response(jsonEncode(payload), 200),
      ),
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
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'code': 'pregnancy_scope_denied',
            'detail': 'Medication access is not granted.',
          }),
          403,
        ),
      ),
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
      httpClient: MockClient(
        (_) async => http.Response(jsonEncode(payload), 200),
      ),
    );

    final result = await api.list(
      fromDate: DateTime(2026, 9, 14),
      toDate: DateTime(2026, 9, 20),
    );
    expect(result.treatmentPlans, isEmpty);
    expect(result.doseOccurrences, isEmpty);
    expect(result.typedTreatmentPlans, isEmpty);
    expect(result.typedDoseOccurrences, isEmpty);
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
