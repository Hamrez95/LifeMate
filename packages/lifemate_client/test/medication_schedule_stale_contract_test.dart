import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test('stale preference write surfaces 409 without retrying as success', () async {
    var calls = 0;
    final api = LifeMateMedicationScheduleApi(
      baseUri: Uri.parse('https://example.test'),
      accessToken: () => 'token',
      httpClient: MockClient((request) async {
        calls++;
        return http.Response(
          jsonEncode({
            'code': 'stale_schedule_preferences',
            'detail': 'Schedule preferences changed. Refresh and try again.',
          }),
          409,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await expectLater(
      api.savePreferences(
        current: const LifeMateMedicationSchedulePreferences(
          timeZone: 'Asia/Tehran',
          sleepWindowEnabled: false,
          sleepStartLocalTime: null,
          sleepEndLocalTime: null,
          version: 2,
        ),
        timeZone: 'Asia/Tehran',
        sleepWindowEnabled: true,
        sleepStartLocalTime: '23:00',
        sleepEndLocalTime: '07:00',
      ),
      throwsA(
        isA<LifeMateApiException>()
            .having((error) => error.statusCode, 'statusCode', 409)
            .having(
              (error) => error.code,
              'code',
              'stale_schedule_preferences',
            ),
      ),
    );
    expect(calls, 1);
    api.close();
  });

  test('invalid server-side timing input remains a 400 contract failure', () async {
    final api = LifeMateMedicationScheduleApi(
      baseUri: Uri.parse('https://example.test'),
      accessToken: () => 'token',
      httpClient: MockClient((request) async {
        expect(request.method, 'PATCH');
        return http.Response(
          jsonEncode({
            'code': 'invalid_manual_spacing_before_minutes',
            'detail': 'manual spacing must be bounded',
          }),
          400,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await expectLater(
      api.savePlanTiming(
        current: const LifeMateTreatmentPlanTiming(
          treatmentPlanId: '11111111-1111-1111-1111-111111111111',
          treatmentPlanVersion: 3,
          nearbyGroupingEnabled: false,
          timingLocked: false,
          manualSpacingBeforeMinutes: 0,
          manualSpacingAfterMinutes: 0,
          timingNote: null,
          version: 1,
        ),
        nearbyGroupingEnabled: true,
        timingLocked: false,
        manualSpacingBeforeMinutes: -1,
        manualSpacingAfterMinutes: 0,
      ),
      throwsA(
        isA<LifeMateApiException>()
            .having((error) => error.statusCode, 'statusCode', 400)
            .having(
              (error) => error.code,
              'code',
              'invalid_manual_spacing_before_minutes',
            ),
      ),
    );
    api.close();
  });
}
