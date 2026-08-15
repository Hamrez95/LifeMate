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

  test('privacy-safe crash event never serializes message or raw stack', () {
    final event = PrivacySafeCrashEvent.fromError(
      application: 'wellmate',
      releaseVersion: '0.9.0-internal.9+20',
      error: StateError(
        'patient@example.test medication=private Bearer secret-token',
      ),
      stackTrace: StackTrace.fromString(
        '#0 patient@example.test Bearer secret-token\n#1 medication-private',
      ),
      source: LifeMateCrashSource.flutterFramework,
      fatal: false,
    );

    final encoded = jsonEncode(event.toJson());
    expect(event.errorType, 'StateError');
    expect(event.stackFingerprint, matches(RegExp(r'^[0-9a-f]{16}$')));
    expect(encoded, isNot(contains('patient@example.test')));
    expect(encoded, isNot(contains('secret-token')));
    expect(encoded, isNot(contains('medication-private')));
    expect(event.toJson().keys, <String>{
      'eventId',
      'application',
      'releaseVersion',
      'platform',
      'source',
      'errorType',
      'stackFingerprint',
      'fatal',
    });
  });

  test('reporter sends only bounded envelope to authenticated telemetry', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response('{"accepted":true}', 202);
    });
    final reporter = LifeMateCrashReporter(
      config: config,
      application: 'caremate',
      releaseVersion: '0.9.0-internal.9+20',
      accessToken: () async => 'test-access-token',
      httpClient: client,
    );

    await reporter.report(
      StateError('private patient detail'),
      StackTrace.fromString('private stack and token'),
      source: LifeMateCrashSource.zone,
      fatal: true,
    );
    reporter.close();

    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(captured.url.path, '/functions/v1/lifemate-telemetry');
    expect(captured.headers['authorization'], 'Bearer test-access-token');
    expect(body['application'], 'caremate');
    expect(body['source'], 'zone');
    expect(body['fatal'], true);
    expect(captured.body, isNot(contains('private patient detail')));
    expect(captured.body, isNot(contains('private stack')));
    expect(captured.body, isNot(contains('test-access-token')));
    expect(body.keys.toSet(), <String>{
      'eventId',
      'application',
      'releaseVersion',
      'platform',
      'source',
      'errorType',
      'stackFingerprint',
      'fatal',
    });
  });

  test('reporter fails closed when no authenticated session exists', () async {
    var called = false;
    final client = MockClient((_) async {
      called = true;
      return http.Response('', 202);
    });
    final reporter = LifeMateCrashReporter(
      config: config,
      application: 'wellmate',
      releaseVersion: '0.9.0-internal.9+20',
      accessToken: () async => null,
      httpClient: client,
    );

    await reporter.report(
      Exception('private'),
      StackTrace.current,
      source: LifeMateCrashSource.platformDispatcher,
      fatal: true,
    );
    reporter.close();

    expect(called, isFalse);
  });
}
