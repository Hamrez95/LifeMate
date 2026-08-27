import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test('feedback API sends canonical context and stable idempotency key', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(jsonEncode({'itemId': 'item-1'}), 201);
    });
    final api = LifeMateFeedbackApi(
      baseUri: Uri.parse('https://example.test/functions/v1/lifemate-api'),
      accessToken: () => 'token',
      httpClient: client,
    );
    addTearDown(api.close);

    await api.submit(
      const LifeMateFeedbackSubmission(
        kind: LifeMateFeedbackKind.featureRequest,
        productCode: 'wellmate',
        appVersion: '0.9.0-internal.9+20',
        buildNumber: '20',
        idempotencyKey: 'request-123',
        message: 'Calendar search',
      ),
    );

    expect(captured.url.path, '/functions/v1/lifemate-api/api/v1/feedback');
    expect(captured.headers['Idempotency-Key'], 'request-123');
    final payload = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(payload['kind'], 'FeatureRequest');
    expect(payload['productCode'], 'wellmate');
    expect(payload['appVersion'], '0.9.0-internal.9+20');
    expect(payload['buildNumber'], '20');
    expect(payload.containsKey('npsScore'), isFalse);
    expect(payload.containsKey('advocacyOptIn'), isFalse);
  });

  test('advocacy payload only opts in when user explicitly selected it', () {
    const submission = LifeMateFeedbackSubmission(
      kind: LifeMateFeedbackKind.advocacy,
      productCode: 'caremate',
      idempotencyKey: 'request-456',
      message: 'I want to help',
      advocacyOptIn: true,
    );

    expect(submission.toJson()['advocacyOptIn'], isTrue);
  });
}
