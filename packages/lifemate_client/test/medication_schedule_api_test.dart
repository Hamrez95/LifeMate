import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test('uninitialized preferences parse with version zero', () {
    final value = LifeMateMedicationSchedulePreferences.fromJson(const {
      'timeZone': 'Asia/Tehran',
      'sleepWindowEnabled': false,
      'sleepStartLocalTime': null,
      'sleepEndLocalTime': null,
      'version': 0,
    });
    expect(value.version, 0);
    expect(value.sleepWindowEnabled, isFalse);
  });

  test('active timing plans preserve canonical hourly recurrence', () async {
    final api = LifeMateMedicationScheduleApi(
      baseUri: Uri.parse('https://example.test'),
      accessToken: () => 'token',
      httpClient: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/v1/medication-schedule/plans');
        return http.Response(
          jsonEncode({
            'items': [
              {
                'treatmentPlanId': '11111111-1111-1111-1111-111111111111',
                'treatmentPlanVersion': 4,
                'medicationName': 'Example medicine',
                'strengthText': '10 mg',
                'recurrence': {'enabled': true, 'unit': 'hour', 'interval': 48},
                'recurrenceStartLocalTime': '08:00',
                'nearbyGroupingEnabled': false,
                'timingLocked': true,
                'manualSpacingBeforeMinutes': 0,
                'manualSpacingAfterMinutes': 0,
                'timingNote': null,
                'version': 2,
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final plans = await api.listPlans();
    expect(plans, hasLength(1));
    expect(plans.single.medicationName, 'Example medicine');
    expect(plans.single.recurrence?['unit'], 'hour');
    expect(plans.single.recurrence?['interval'], 48);
    expect(plans.single.recurrenceStartLocalTime, '08:00');
    expect(plans.single.timing.timingLocked, isTrue);
    expect(plans.single.timing.treatmentPlanVersion, 4);
    api.close();
  });

  test('preference PATCH is versioned and idempotent at transport boundary', () async {
    late http.Request captured;
    final api = LifeMateMedicationScheduleApi(
      baseUri: Uri.parse('https://example.test'),
      accessToken: () => 'token',
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'timeZone': 'Asia/Tehran',
            'sleepWindowEnabled': true,
            'sleepStartLocalTime': '23:00:00',
            'sleepEndLocalTime': '07:00:00',
            'version': 1,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final updated = await api.savePreferences(
      current: const LifeMateMedicationSchedulePreferences(
        timeZone: 'Asia/Tehran',
        sleepWindowEnabled: false,
        sleepStartLocalTime: null,
        sleepEndLocalTime: null,
        version: 0,
      ),
      timeZone: 'Asia/Tehran',
      sleepWindowEnabled: true,
      sleepStartLocalTime: '23:00',
      sleepEndLocalTime: '07:00',
    );

    expect(captured.method, 'PATCH');
    expect(captured.url.path, '/api/v1/medication-schedule/preferences');
    expect(captured.headers['idempotency-key'], isNotEmpty);
    final payload = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(payload['version'], 0);
    expect(payload['sleepWindowEnabled'], isTrue);
    expect(payload.containsKey('medication'), isFalse);
    expect(payload.containsKey('dose'), isFalse);
    expect(updated.version, 1);
    api.close();
  });

  test('plan timing PATCH carries both plan and timing versions', () async {
    late http.Request captured;
    final api = LifeMateMedicationScheduleApi(
      baseUri: Uri.parse('https://example.test'),
      accessToken: () => 'token',
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'treatmentPlanId': '11111111-1111-1111-1111-111111111111',
            'treatmentPlanVersion': 7,
            'nearbyGroupingEnabled': true,
            'timingLocked': true,
            'manualSpacingBeforeMinutes': 30,
            'manualSpacingAfterMinutes': 45,
            'timingNote': 'User supplied constraint',
            'version': 3,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await api.savePlanTiming(
      current: const LifeMateTreatmentPlanTiming(
        treatmentPlanId: '11111111-1111-1111-1111-111111111111',
        treatmentPlanVersion: 7,
        nearbyGroupingEnabled: false,
        timingLocked: false,
        manualSpacingBeforeMinutes: 0,
        manualSpacingAfterMinutes: 0,
        timingNote: null,
        version: 2,
      ),
      nearbyGroupingEnabled: true,
      timingLocked: true,
      manualSpacingBeforeMinutes: 30,
      manualSpacingAfterMinutes: 45,
      timingNote: 'User supplied constraint',
    );

    expect(
      captured.url.path,
      '/api/v1/treatment-plans/11111111-1111-1111-1111-111111111111/timing',
    );
    final payload = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(payload['version'], 2);
    expect(payload['treatmentPlanVersion'], 7);
    expect(payload['manualSpacingBeforeMinutes'], 30);
    expect(payload['manualSpacingAfterMinutes'], 45);
    expect(captured.headers['idempotency-key'], isNotEmpty);
    api.close();
  });

  test('missing session fails closed without network', () async {
    var called = false;
    final api = LifeMateMedicationScheduleApi(
      baseUri: Uri.parse('https://example.test'),
      accessToken: () => null,
      httpClient: MockClient((_) async {
        called = true;
        return http.Response('{}', 200);
      }),
    );

    await expectLater(
      api.getPreferences(),
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
