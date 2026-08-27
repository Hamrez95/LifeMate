import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wellmate/screens/onboarding/wellmate_first_value_api.dart';

void main() {
  const profile = <String, dynamic>{
    'version': 4,
    'displayName': 'Owner',
    'phoneNumber': null,
    'locale': 'fa',
    'timeZone': 'Asia/Tehran',
    'avatarKey': 'person_green',
    'presentationIntent': 'Self',
    'wellMateFirstValueState': null,
  };

  test('reads first-value state from canonical profile endpoint', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/v1/me/profile');
      expect(request.headers['authorization'], 'Bearer token');
      return http.Response(jsonEncode(profile), 200);
    });
    final api = WellMateFirstValueApi(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'token',
      httpClient: client,
    );

    final value = await api.getProfile();
    expect(value.version, 4);
    expect(value.state, isNull);
    expect(value.isResolved, isFalse);
  });

  test('skip persists only presentation state through profile PATCH', () async {
    final client = MockClient((request) async {
      expect(request.method, 'PATCH');
      expect(request.url.path, '/api/v1/me/profile');
      expect(request.headers['idempotency-key'], isNotEmpty);
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['version'], 4);
      expect(body['displayName'], 'Owner');
      expect(body['presentationIntent'], 'Self');
      expect(body['wellMateFirstValueState'], 'Skipped');
      expect(body.containsKey('notificationPermission'), isFalse);
      expect(body.containsKey('relationshipId'), isFalse);
      return http.Response(
        jsonEncode({...profile, 'version': 5, 'wellMateFirstValueState': 'Skipped'}),
        200,
      );
    });
    final api = WellMateFirstValueApi(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'token',
      httpClient: client,
    );
    final current = WellMateFirstValueProfile.fromJson(profile);

    final updated = await api.setState(current: current, state: 'Skipped');
    expect(updated.state, 'Skipped');
    expect(updated.isResolved, isTrue);
  });

  test('unknown state is rejected before network mutation', () async {
    var called = false;
    final api = WellMateFirstValueApi(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'token',
      httpClient: MockClient((request) async {
        called = true;
        return http.Response('{}', 200);
      }),
    );

    await expectLater(
      api.setState(
        current: WellMateFirstValueProfile.fromJson(profile),
        state: 'Authorized',
      ),
      throwsArgumentError,
    );
    expect(called, isFalse);
  });
}
