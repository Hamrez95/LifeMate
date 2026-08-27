import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wellmate/screens/women_calendar/women_health_activation_api.dart';

void main() {
  const baseProfile = <String, dynamic>{
    'version': 0,
    'enabled': false,
    'lastPeriodStart': null,
    'cycleLength': 28,
    'cycleLengthKnown': null,
    'periodLength': 5,
    'periodLengthKnown': null,
    'regularity': null,
  };

  test('regular activation writes canonical cycle metadata only', () async {
    Map<String, dynamic>? sent;
    final client = MockClient((request) async {
      expect(request.method, 'PATCH');
      expect(request.url.path, '/api/v1/women-calendar/profile');
      expect(request.headers['idempotency-key'], isNotEmpty);
      sent = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          ...baseProfile,
          'version': 1,
          'enabled': true,
          'lastPeriodStart': '2026-08-20',
          'cycleLength': 29,
          'cycleLengthKnown': true,
          'periodLength': 6,
          'periodLengthKnown': true,
          'regularity': 'regular',
        }),
        200,
      );
    });
    final api = WomenHealthActivationApi(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'token',
      httpClient: client,
    );

    final updated = await api.activate(
      current: WomenHealthActivationProfile.fromJson(baseProfile),
      lastPeriodStart: DateTime(2026, 8, 20),
      cycleLength: 29,
      cycleLengthKnown: true,
      periodLength: 6,
      periodLengthKnown: true,
      regularity: 'regular',
    );

    expect(updated.enabled, isTrue);
    expect(updated.cycleLengthKnown, isTrue);
    expect(sent?['regularity'], 'regular');
    expect(sent?.containsKey('mood'), isFalse);
    expect(sent?.containsKey('symptoms'), isFalse);
    expect(sent?.containsKey('privateNotes'), isFalse);
    expect(sent?.containsKey('fertilityIntent'), isFalse);
  });

  test('unknown and irregular remain explicit instead of inferred', () async {
    final requests = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      requests.add(body);
      return http.Response(
        jsonEncode({
          ...baseProfile,
          'version': requests.length,
          'enabled': true,
          'lastPeriodStart': body['lastPeriodStart'],
          'cycleLength': body['cycleLength'],
          'cycleLengthKnown': body['cycleLengthKnown'],
          'periodLength': body['periodLength'],
          'periodLengthKnown': body['periodLengthKnown'],
          'regularity': body['regularity'],
        }),
        200,
      );
    });
    final api = WomenHealthActivationApi(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'token',
      httpClient: client,
    );
    final initial = WomenHealthActivationProfile.fromJson(baseProfile);

    await api.activate(
      current: initial,
      lastPeriodStart: DateTime(2026, 8, 20),
      cycleLength: 28,
      cycleLengthKnown: false,
      periodLength: 5,
      periodLengthKnown: false,
      regularity: 'unknown',
    );
    await api.activate(
      current: initial,
      lastPeriodStart: DateTime(2026, 8, 20),
      cycleLength: 28,
      cycleLengthKnown: false,
      periodLength: 5,
      periodLengthKnown: true,
      regularity: 'irregular',
    );

    expect(requests[0]['cycleLengthKnown'], isFalse);
    expect(requests[0]['periodLengthKnown'], isFalse);
    expect(requests[0]['regularity'], 'unknown');
    expect(requests[1]['cycleLengthKnown'], isFalse);
    expect(requests[1]['regularity'], 'irregular');
  });

  test('invalid regularity never reaches the network', () async {
    var called = false;
    final api = WomenHealthActivationApi(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'token',
      httpClient: MockClient((request) async {
        called = true;
        return http.Response('{}', 200);
      }),
    );

    await expectLater(
      api.activate(
        current: WomenHealthActivationProfile.fromJson(baseProfile),
        lastPeriodStart: DateTime(2026, 8, 20),
        cycleLength: 28,
        cycleLengthKnown: true,
        periodLength: 5,
        periodLengthKnown: true,
        regularity: 'fertile',
      ),
      throwsArgumentError,
    );
    expect(called, isFalse);
  });
}
