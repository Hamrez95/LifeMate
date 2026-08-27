import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test('guidance impression sends only safe identifiers and category', () async {
    Map<String, dynamic>? body;
    final api = LifeMateCompanionCareApi(
      baseUri: Uri.parse('https://example.test'),
      accessToken: () => 'token',
      httpClient: MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer token');
        expect(request.headers['Idempotency-Key'], isNotEmpty);
        body = Map<String, dynamic>.from(jsonDecode(request.body) as Map);
        return http.Response(
          '{"id":"11111111-1111-4111-8111-111111111111","replayed":false}',
          200,
        );
      }),
    );

    await api.recordImpression(
      patientUserId: '22222222-2222-4222-8222-222222222222',
      guidanceId: 'phase.be_present',
      contentVersion: 'companion-care-v1',
      category: 'phase',
    );

    expect(body, {
      'actionType': 'guidance_impression',
      'guidanceId': 'phase.be_present',
      'contentVersion': 'companion-care-v1',
      'category': 'phase',
    });
    for (final forbidden in [
      'privateNotes',
      'symptoms',
      'painLevel',
      'mood',
      'energyLevel',
      'fertility',
    ]) {
      expect(body!.containsKey(forbidden), isFalse);
    }
    api.close();
  });
}
