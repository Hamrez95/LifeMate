import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test('notification completion fails closed when care event changed', () async {
    var patchCalled = false;
    final api = LifeMateEditApi(
      baseUri: Uri.parse('https://api.example.test/functions/v1/lifemate-api'),
      accessToken: () => 'token',
      httpClient: MockClient((request) async {
        if (request.method == 'PATCH') patchCalled = true;
        return http.Response(
          jsonEncode({
            'id': 'event-1',
            'eventType': 'appointment',
            'title': 'visit',
            'scheduledLocalDate': '2026-08-26',
            'scheduledLocalTime': '18:30',
            'timeZone': 'Asia/Tehran',
            'version': 4,
          }),
          200,
        );
      }),
    );

    await expectLater(
      api.updateCareEventStatus(
        eventId: 'event-1',
        status: 'completed',
        expectedVersion: 3,
      ),
      throwsA(
        isA<LifeMateApiException>().having(
          (error) => error.code,
          'code',
          'stale_care_event',
        ),
      ),
    );
    expect(patchCalled, isFalse);
  });
}
