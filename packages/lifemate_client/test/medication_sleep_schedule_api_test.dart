import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test('flexible preview carries explicit bound and effective range', () async {
    late http.Request captured;
    final api = LifeMateMedicationSleepScheduleApi(
      baseUri: Uri.parse('https://example.test'),
      accessToken: () => 'token',
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'runId': '11111111-1111-1111-1111-111111111111',
            'mode': 'flexible_interval',
            'algorithmVersion': 'sleep-flex-v1',
            'consentTextVersion': 'sleep-flex-consent-v1',
            'effectiveFromLocalDate': '2026-09-01',
            'effectiveUntilLocalDate': '2026-09-07',
            'maxVariationMinutes': 30,
            'expiresAtUtc': '2026-09-01T12:00:00Z',
            'proposals': [],
            'exclusions': [],
          }),
          201,
        );
      }),
    );

    await api.preview(
      mode: LifeMateSleepOptimizationMode.flexibleInterval,
      effectiveFrom: DateTime(2026, 9, 1),
      effectiveUntil: DateTime(2026, 9, 7),
      maxVariationMinutes: 30,
    );

    final payload = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(captured.method, 'POST');
    expect(
      captured.url.path,
      '/api/v1/medication-schedule-optimizations/sleep/preview',
    );
    expect(payload['mode'], 'flexible_interval');
    expect(payload['maxVariationMinutes'], 30);
    expect(payload['effectiveFromLocalDate'], '2026-09-01');
    expect(payload['effectiveUntilLocalDate'], '2026-09-07');
    expect(captured.headers['idempotency-key'], isNotEmpty);
    api.close();
  });

  test('strict preview does not send a flexible variation bound', () async {
    late http.Request captured;
    final api = LifeMateMedicationSleepScheduleApi(
      baseUri: Uri.parse('https://example.test'),
      accessToken: () => 'token',
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'runId': '11111111-1111-1111-1111-111111111111',
            'mode': 'strict_anchor_shift',
            'algorithmVersion': 'sleep-flex-v1',
            'consentTextVersion': 'sleep-flex-consent-v1',
            'effectiveFromLocalDate': '2026-09-01',
            'effectiveUntilLocalDate': '2026-09-07',
            'maxVariationMinutes': null,
            'proposals': [],
            'exclusions': [],
          }),
          201,
        );
      }),
    );

    await api.preview(
      mode: LifeMateSleepOptimizationMode.strictAnchorShift,
      effectiveFrom: DateTime(2026, 9, 1),
      effectiveUntil: DateTime(2026, 9, 7),
    );

    final payload = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(payload['mode'], 'strict_anchor_shift');
    expect(payload.containsKey('maxVariationMinutes'), isFalse);
    api.close();
  });

  test('apply sends explicit timing acknowledgement and selected mode', () async {
    late http.Request captured;
    final api = LifeMateMedicationSleepScheduleApi(
      baseUri: Uri.parse('https://example.test'),
      accessToken: () => 'token',
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'runId': '11111111-1111-1111-1111-111111111111',
            'status': 'applied',
            'mode': 'flexible_interval',
            'effectiveFromLocalDate': '2026-09-01',
            'effectiveUntilLocalDate': '2026-09-07',
            'consentTextVersion': 'sleep-flex-consent-v1',
          }),
          200,
        );
      }),
    );

    await api.apply(
      preview: LifeMateSleepOptimizationPreview.fromJson(const {
        'runId': '11111111-1111-1111-1111-111111111111',
        'mode': 'flexible_interval',
        'algorithmVersion': 'sleep-flex-v1',
        'consentTextVersion': 'sleep-flex-consent-v1',
        'effectiveFromLocalDate': '2026-09-01',
        'effectiveUntilLocalDate': '2026-09-07',
        'maxVariationMinutes': 30,
        'proposals': [],
        'exclusions': [],
      }),
    );

    final payload = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(payload['mode'], 'flexible_interval');
    expect(payload['acknowledgedTimingChanges'], isTrue);
    expect(captured.headers['idempotency-key'], isNotEmpty);
    api.close();
  });

  test('undo is an idempotent authenticated mutation', () async {
    late http.Request captured;
    final api = LifeMateMedicationSleepScheduleApi(
      baseUri: Uri.parse('https://example.test'),
      accessToken: () => 'token',
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response('{"runId":"run","status":"undone"}', 200);
      }),
    );

    await api.undo('11111111-1111-1111-1111-111111111111');
    expect(captured.method, 'POST');
    expect(
      captured.url.path,
      '/api/v1/medication-schedule-optimizations/11111111-1111-1111-1111-111111111111/undo',
    );
    expect(captured.headers['idempotency-key'], isNotEmpty);
    api.close();
  });

  test('missing session fails closed without network', () async {
    var called = false;
    final api = LifeMateMedicationSleepScheduleApi(
      baseUri: Uri.parse('https://example.test'),
      accessToken: () => null,
      httpClient: MockClient((_) async {
        called = true;
        return http.Response('{}', 200);
      }),
    );

    await expectLater(
      api.active(),
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
