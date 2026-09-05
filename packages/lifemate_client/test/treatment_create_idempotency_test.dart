import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test('treatment create reuses caller request id across retry', () async {
    var requestCount = 0;
    final idempotencyKeys = <String?>[];
    const requestId = 'offline-treatment-create-832-0001';
    final api = LifeMateApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'access-token',
      httpClient: MockClient((request) async {
        requestCount += 1;
        idempotencyKeys.add(request.headers['idempotency-key']);
        if (requestCount == 1) {
          return http.Response(
            jsonEncode({'code': 'temporary_unavailable'}),
            503,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({'id': '123e4567-e89b-42d3-a456-426614174777'}),
          201,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final result = await api.createTreatmentPlan(
      clientRequestId: requestId,
      medicationId: '123e4567-e89b-42d3-a456-426614174701',
      doseText: '1 tablet',
      startDate: DateTime(2026, 9, 5),
      timeZone: 'Asia/Tehran',
      schedules: const [
        {'dayOfWeek': 'saturday', 'localTime': '08:30'},
      ],
    );

    expect(result['id'], '123e4567-e89b-42d3-a456-426614174777');
    expect(requestCount, 2);
    expect(idempotencyKeys, everyElement(requestId));
  });
}
