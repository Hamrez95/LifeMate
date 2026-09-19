import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate_client/src/cocoon_pregnancy_measurements_api.dart';
import 'package:lifemate_client/src/lifemate_api_client.dart';

void main() {
  const requestId = '123e4567-e89b-42d3-a456-426614174000';

  Map<String, dynamic> observation({
    String id = '11111111-1111-4111-8111-111111111111',
    String type = 'weight',
    double primary = 68.5,
    double? secondary,
  }) => {
    'id': id,
    'personId': '22222222-2222-4222-8222-222222222222',
    'observationType': type,
    'valuePrimary': primary,
    'valueSecondary': secondary,
    'unitPrimary': type == 'weight' ? 'kg' : 'mmHg',
    'unitSecondary': type == 'blood_pressure' ? 'mmHg' : null,
    'note': null,
    'observedAtUtc': '2026-09-14T09:00:00.000Z',
    'observedLocalDate': '2026-09-14',
    'timeZone': 'Asia/Tehran',
    'sourceCategory': 'FirstPartyUserInput',
    'sourceProvider': 'cocoonmate',
    'sourceApplicationCode': 'cocoonmate',
    'version': 1,
  };

  test('lists only the canonical pregnancy measurement projection', () async {
    late http.Request captured;
    final api = CocoonPregnancyMeasurementsApiClient(
      baseUri: Uri.parse('https://example.test'),
      accessToken: () => 'token',
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'contractVersion': 1,
            'episodeId': '33333333-3333-4333-8333-333333333333',
            'inputSchema': [
              {
                'observationType': 'weight',
                'fields': [
                  {
                    'wireField': 'valuePrimary',
                    'semanticRole': 'weight',
                    'unit': 'kg',
                  },
                ],
              },
              {
                'observationType': 'blood_pressure',
                'fields': [
                  {
                    'wireField': 'valuePrimary',
                    'semanticRole': 'systolic',
                    'unit': 'mmHg',
                  },
                  {
                    'wireField': 'valueSecondary',
                    'semanticRole': 'diastolic',
                    'unit': 'mmHg',
                  },
                ],
              },
              {
                'observationType': 'blood_glucose',
                'fields': [
                  {
                    'wireField': 'valuePrimary',
                    'semanticRole': 'blood_glucose',
                    'unit': 'mg/dL',
                  },
                ],
              },
            ],
            'items': [observation()],
          }),
          200,
        );
      }),
    );

    final result = await api.list(
      fromDate: DateTime(2026, 9, 1),
      toDate: DateTime(2026, 9, 14),
    );

    expect(captured.method, 'GET');
    expect(captured.url.path, '/api/v1/cocoon/pregnancy/measurements');
    expect(captured.url.queryParameters['fromDate'], '2026-09-01');
    expect(captured.url.queryParameters['toDate'], '2026-09-14');
    expect(captured.headers.containsKey('Idempotency-Key'), isFalse);
    expect(result.items.single.observationType, 'weight');
    expect(result.items.single.unitPrimary, 'kg');
    final bpSchema = result.schemaFor(
      CocoonPregnancyMeasurementType.bloodPressure,
    );
    expect(bpSchema, isNotNull);
    expect(
      bpSchema!.fields.map((field) => field.semanticRole).toList(),
      [
        CocoonPregnancyMeasurementSemanticRole.systolic,
        CocoonPregnancyMeasurementSemanticRole.diastolic,
      ],
    );
    expect(
      bpSchema.fields.map((field) => field.unit).toList(),
      ['mmHg', 'mmHg'],
    );
    expect(
      result
          .schemaFor(CocoonPregnancyMeasurementType.bloodGlucose)!
          .fields
          .single
          .unit,
      'mg/dL',
    );
    api.close();
  });

  test('create reuses canonical observation payload and stable idempotency key', () async {
    late http.Request captured;
    final api = CocoonPregnancyMeasurementsApiClient(
      baseUri: Uri.parse('https://example.test'),
      accessToken: () => 'token',
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'contractVersion': 1,
            'episodeId': '33333333-3333-4333-8333-333333333333',
            'observation': observation(
              type: 'blood_pressure',
              primary: 118,
              secondary: 76,
            ),
          }),
          201,
        );
      }),
    );

    final result = await api.create(
      clientRequestId: requestId,
      type: CocoonPregnancyMeasurementType.bloodPressure,
      valuePrimary: 118,
      valueSecondary: 76,
      observedAtUtc: DateTime.utc(2026, 9, 14, 9),
      observedLocalDate: DateTime(2026, 9, 14, 12, 30),
      timeZone: 'Asia/Tehran',
    );

    expect(captured.url.path, '/api/v1/cocoon/pregnancy/measurements');
    expect(captured.headers['Idempotency-Key'], requestId);
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['clientRequestId'], requestId);
    expect(body['observationType'], 'blood_pressure');
    expect(body['valuePrimary'], 118);
    expect(body['valueSecondary'], 76);
    expect(body['observedLocalDate'], '2026-09-14');
    expect(body.containsKey('unitPrimary'), isFalse);
    expect(result.observation.sourceApplicationCode, 'cocoonmate');
    api.close();
  });

  test('existing canonical observation link has its own stable mutation key', () async {
    late http.Request captured;
    final api = CocoonPregnancyMeasurementsApiClient(
      baseUri: Uri.parse('https://example.test'),
      accessToken: () => 'token',
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'contractVersion': 1,
            'episodeId': '33333333-3333-4333-8333-333333333333',
            'observationId': '11111111-1111-4111-8111-111111111111',
          }),
          200,
        );
      }),
    );

    final result = await api.linkExisting(
      clientRequestId: requestId,
      observationId: '11111111-1111-4111-8111-111111111111',
    );

    expect(captured.url.path, '/api/v1/cocoon/pregnancy/measurement-links');
    expect(captured.headers['Idempotency-Key'], requestId);
    expect(
      jsonDecode(captured.body),
      {'observationId': '11111111-1111-4111-8111-111111111111'},
    );
    expect(result.observationId, '11111111-1111-4111-8111-111111111111');
    api.close();
  });

  test('revoked pregnancy observation access fails closed', () async {
    final api = CocoonPregnancyMeasurementsApiClient(
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
        fromDate: DateTime(2026, 9, 14),
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

  test('missing session fails before measurement network access', () async {
    var called = false;
    final api = CocoonPregnancyMeasurementsApiClient(
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

  test('measurement schema rejects unknown semantic roles instead of guessing UI meaning', () {
    expect(
      () => CocoonPregnancyMeasurements.fromJson({
        'contractVersion': 1,
        'episodeId': '33333333-3333-4333-8333-333333333333',
        'inputSchema': [
          {
            'observationType': 'blood_pressure',
            'fields': [
              {
                'wireField': 'valuePrimary',
                'semanticRole': 'invented-pressure-role',
                'unit': 'mmHg',
              },
            ],
          },
        ],
        'items': <Object?>[],
      }),
      throwsFormatException,
    );
  });

}
