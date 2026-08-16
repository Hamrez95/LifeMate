import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  const config = AppConfig(
    supabaseUrl: 'https://example.supabase.co',
    supabasePublishableKey: 'sb_publishable_test_key',
    apiBaseUrl: 'https://api.example.test',
  );

  test('product event serializes only the fixed privacy-safe envelope', () {
    final event = PrivacySafeProductEvent.create(
      application: 'WellMate',
      releaseVersion: '0.9.0-internal.9+20',
      event: LifeMateProductEvent.onboardingCompleted,
      localeFamily: LifeMateLocaleFamily.fa,
      connectivity: LifeMateConnectivityClass.online,
      outcome: LifeMateTelemetryOutcome.success,
    );

    final body = event.toJson();
    expect(body['kind'], 'product');
    expect(body['application'], 'wellmate');
    expect(body['eventName'], 'onboarding_completed');
    expect(body['localeFamily'], 'fa');
    expect(body['connectivity'], 'online');
    expect(body['outcome'], 'success');
    expect(body.keys.toSet(), <String>{
      'kind',
      'eventId',
      'application',
      'releaseVersion',
      'platform',
      'eventName',
      'localeFamily',
      'connectivity',
      'outcome',
    });
    final encoded = jsonEncode(body);
    for (final forbidden in <String>[
      'userId',
      'personId',
      'patient@example.test',
      'medication',
      'symptom',
      'cycleDate',
      'note',
      '/api/v1/',
    ]) {
      expect(encoded, isNot(contains(forbidden)));
    }
  });

  test('analytics reporter sends only the bounded authenticated envelope', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response('{"accepted":true}', 202);
    });
    final analytics = LifeMateProductAnalytics(
      config: config,
      application: 'caremate',
      releaseVersion: '0.9.0-internal.9+20',
      accessToken: () async => 'test-access-token',
      httpClient: client,
    );

    await analytics.track(
      LifeMateProductEvent.carePairingCompleted,
      localeFamily: LifeMateLocaleFamily.en,
      connectivity: LifeMateConnectivityClass.recovering,
      outcome: LifeMateTelemetryOutcome.success,
    );
    analytics.close();

    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(captured.url.path, '/functions/v1/lifemate-telemetry');
    expect(captured.headers['authorization'], 'Bearer test-access-token');
    expect(body['kind'], 'product');
    expect(body['application'], 'caremate');
    expect(body['eventName'], 'care_pairing_completed');
    expect(body['connectivity'], 'recovering');
    expect(captured.body, isNot(contains('test-access-token')));
    expect(body.keys.toSet(), <String>{
      'kind',
      'eventId',
      'application',
      'releaseVersion',
      'platform',
      'eventName',
      'localeFamily',
      'connectivity',
      'outcome',
    });
  });

  test('analytics fails closed without a valid app or authenticated session', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls += 1;
      return http.Response('', 202);
    });

    final noSession = LifeMateProductAnalytics(
      config: config,
      application: 'wellmate',
      releaseVersion: '0.9.0',
      accessToken: () async => null,
      httpClient: client,
    );
    await noSession.track(LifeMateProductEvent.appOpen);
    noSession.close();

    final invalidApp = LifeMateProductAnalytics(
      config: config,
      application: 'patient-private-name',
      releaseVersion: '0.9.0',
      accessToken: () async => 'token',
      httpClient: client,
    );
    await invalidApp.track(LifeMateProductEvent.appOpen);
    invalidApp.close();

    expect(calls, 0);
  });
}
