import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  const baseProfile = <String, dynamic>{
    'version': 4,
    'displayName': 'Existing name',
    'phoneNumber': null,
    'locale': 'fa',
    'timeZone': 'Asia/Tehran',
    'avatarKey': 'person_blue',
    'presentationIntent': null,
    'onboardingCompleted': false,
  };

  test('completed server snapshot parses as existing-user bypass state', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/v1/me/profile');
      return http.Response(
        jsonEncode({...baseProfile, 'onboardingCompleted': true}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final api = LifeMateAccountOnboardingApi(
      baseUri: Uri.parse('https://example.test'),
      accessToken: () => 'token',
      httpClient: client,
    );

    final snapshot = await api.getSnapshot();
    expect(snapshot.completed, isTrue);
    expect(snapshot.version, 4);
    expect(snapshot.presentationIntent, isNull);
    api.close();
  });

  test('completion PATCH preserves profile fields and sends intent only as metadata', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          ...baseProfile,
          ...body,
          'version': 5,
          'onboardingCompleted': true,
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final api = LifeMateAccountOnboardingApi(
      baseUri: Uri.parse('https://example.test'),
      accessToken: () => 'token',
      httpClient: client,
    );
    final current = LifeMateAccountOnboardingSnapshot.fromJson(baseProfile);

    final updated = await api.complete(
      current: current,
      displayName: '  حمید  ',
      intent: LifeMatePresentationIntent.both,
    );

    expect(captured.method, 'PATCH');
    expect(captured.url.path, '/api/v1/me/profile');
    expect(captured.headers['idempotency-key'], isNotEmpty);
    final payload = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(payload['version'], 4);
    expect(payload['displayName'], 'حمید');
    expect(payload['locale'], 'fa');
    expect(payload['timeZone'], 'Asia/Tehran');
    expect(payload['avatarKey'], 'person_blue');
    expect(payload['presentationIntent'], 'Both');
    expect(payload['completeOnboarding'], isTrue);
    expect(payload.containsKey('permission'), isFalse);
    expect(payload.containsKey('consent'), isFalse);
    expect(payload.containsKey('relationship'), isFalse);
    expect(updated.completed, isTrue);
    expect(updated.presentationIntent, LifeMatePresentationIntent.both);
    api.close();
  });

  test('missing session fails closed before network access', () async {
    var called = false;
    final api = LifeMateAccountOnboardingApi(
      baseUri: Uri.parse('https://example.test'),
      accessToken: () => null,
      httpClient: MockClient((_) async {
        called = true;
        return http.Response('{}', 200);
      }),
    );

    await expectLater(
      api.getSnapshot(),
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
