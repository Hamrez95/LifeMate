import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate_client/lifemate_client.dart';

const _subjectA = '11111111-1111-4111-8111-111111111111';
const _subjectB = '22222222-2222-4222-8222-222222222222';

Map<String, dynamic> _snapshot({
  String product = 'wellmate',
  String state = 'current',
  bool flag = true,
  bool failClosed = true,
  DateTime? fetchedAt,
}) => {
  'product': product,
  'platform': 'android',
  'controls': [
    {
      'key': 'client.women_calendar.enabled',
      'kind': 'FeatureFlag',
      'valueType': 'Boolean',
      'value': flag,
      'definitionVersion': 4,
      'source': 'rule',
      'ruleVersion': 2,
      'failClosed': failClosed,
    },
  ],
  'updatePolicy': {
    'updateState': state,
    'minimumSupportedVersion': state == 'force' ? '1.2.0' : null,
    'recommendedVersion': '1.3.0',
    'reasonCode': state == 'force' ? 'Security' : 'Routine',
    'messageKey': null,
    'policyVersion': 3,
  },
  'snapshotVersion': 'controls-4:update-3',
  'fetchedAtUtc': (fetchedAt ?? DateTime.now().toUtc()).toIso8601String(),
  'cacheTtlSeconds': 60,
};

void main() {
  test('fresh account-scoped persistent cache avoids network', () async {
    var networkCalls = 0;
    String? readKey;
    final client = LifeMateRemoteConfigClient(
      baseUri: Uri.parse('https://example.test'),
      product: 'wellmate',
      currentVersion: '1.2.3+42',
      platform: 'android',
      accessToken: () => 'token',
      cacheSubject: () => _subjectA,
      cacheRead: (key) async {
        readKey = key;
        return jsonEncode(_snapshot());
      },
      cacheWrite: (_, __) async {},
      httpClient: MockClient((_) async {
        networkCalls += 1;
        return http.Response('{}', 500);
      }),
    );

    final result = await client.load();
    expect(result.fromCache, isTrue);
    expect(networkCalls, 0);
    expect(readKey, contains(_subjectA));
    expect(result.boolFlag('client.women_calendar.enabled'), isTrue);
    client.close();
  });

  test('different signed-in subjects never share a cache key', () async {
    final keys = <String>[];
    Future<String?> read(String key) async {
      keys.add(key);
      return null;
    }

    http.Response responseFor(http.Request request) =>
        http.Response(jsonEncode(_snapshot()), 200);

    final first = LifeMateRemoteConfigClient(
      baseUri: Uri.parse('https://example.test'),
      product: 'wellmate',
      currentVersion: '1.2.3',
      platform: 'android',
      accessToken: () => 'token-a',
      cacheSubject: () => _subjectA,
      cacheRead: read,
      cacheWrite: (_, __) async {},
      httpClient: MockClient((request) async => responseFor(request)),
    );
    final second = LifeMateRemoteConfigClient(
      baseUri: Uri.parse('https://example.test'),
      product: 'wellmate',
      currentVersion: '1.2.3',
      platform: 'android',
      accessToken: () => 'token-b',
      cacheSubject: () => _subjectB,
      cacheRead: read,
      cacheWrite: (_, __) async {},
      httpClient: MockClient((request) async => responseFor(request)),
    );

    await first.load();
    await second.load();
    expect(keys, hasLength(2));
    expect(keys[0], isNot(keys[1]));
    expect(keys[0], contains(_subjectA));
    expect(keys[1], contains(_subjectB));
    first.close();
    second.close();
  });

  test('missing cache subject skips persistent cache entirely', () async {
    var cacheReads = 0;
    var cacheWrites = 0;
    final client = LifeMateRemoteConfigClient(
      baseUri: Uri.parse('https://example.test'),
      product: 'wellmate',
      currentVersion: '1.2.3',
      platform: 'android',
      accessToken: () => 'token',
      cacheSubject: () => null,
      cacheRead: (_) async {
        cacheReads += 1;
        return jsonEncode(_snapshot());
      },
      cacheWrite: (_, __) async => cacheWrites += 1,
      httpClient: MockClient(
        (_) async => http.Response(jsonEncode(_snapshot()), 200),
      ),
    );

    final result = await client.load();
    expect(result.fromCache, isFalse);
    expect(cacheReads, 0);
    expect(cacheWrites, 0);
    client.close();
  });

  test('stale outage cache fails protected flag closed after 24h', () async {
    final stale = _snapshot(
      flag: true,
      fetchedAt: DateTime.now().toUtc().subtract(const Duration(days: 2)),
    );
    final client = LifeMateRemoteConfigClient(
      baseUri: Uri.parse('https://example.test'),
      product: 'wellmate',
      currentVersion: '1.2.3',
      platform: 'android',
      accessToken: () => 'token',
      cacheSubject: () => _subjectA,
      cacheRead: (_) async => jsonEncode(stale),
      cacheWrite: (_, __) async {},
      httpClient: MockClient(
        (_) async => throw http.ClientException('offline'),
      ),
    );

    final result = await client.load();
    expect(result.fromCache, isTrue);
    expect(result.boolFlag('client.women_calendar.enabled'), isFalse);
    expect(result.isTrustedForUpdatePolicy(DateTime.now()), isFalse);
    client.close();
  });

  test('fresh server snapshot replaces stale cache and keeps force update', () async {
    String? written;
    final client = LifeMateRemoteConfigClient(
      baseUri: Uri.parse('https://example.test'),
      product: 'wellmate',
      currentVersion: '1.1.0',
      platform: 'android',
      accessToken: () => 'token',
      cacheSubject: () => _subjectA,
      cacheRead: (_) async => jsonEncode(
        _snapshot(
          fetchedAt: DateTime.now().toUtc().subtract(const Duration(hours: 2)),
        ),
      ),
      cacheWrite: (_, value) async => written = value,
      httpClient: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/v1/product/runtime-config');
        return http.Response(jsonEncode(_snapshot(state: 'force')), 200);
      }),
    );

    final result = await client.load();
    expect(result.fromCache, isFalse);
    expect(result.updatePolicy.state, LifeMateUpdateState.force);
    expect(result.isTrustedForUpdatePolicy(DateTime.now()), isTrue);
    expect(written, isNotNull);
    client.close();
  });

  test('cache with wrong product is discarded and refreshed', () async {
    var networkCalls = 0;
    final client = LifeMateRemoteConfigClient(
      baseUri: Uri.parse('https://example.test'),
      product: 'wellmate',
      currentVersion: '1.2.3',
      platform: 'android',
      accessToken: () => 'token',
      cacheSubject: () => _subjectA,
      cacheRead: (_) async => jsonEncode(_snapshot(product: 'caremate')),
      cacheWrite: (_, __) async {},
      httpClient: MockClient((_) async {
        networkCalls += 1;
        return http.Response(jsonEncode(_snapshot()), 200);
      }),
    );

    final result = await client.load();
    expect(networkCalls, 1);
    expect(result.product, 'wellmate');
    expect(result.fromCache, isFalse);
    client.close();
  });

  test('version presence excludes device fingerprint and uses idempotency', () async {
    late http.Request captured;
    final client = LifeMateRemoteConfigClient(
      baseUri: Uri.parse('https://example.test'),
      product: 'caremate',
      currentVersion: '0.9.0-internal.9+20',
      platform: 'android',
      accessToken: () => 'token',
      cacheSubject: () => _subjectA,
      cacheRead: (_) async => null,
      cacheWrite: (_, __) async {},
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response('{}', 202);
      }),
    );

    await client.recordVersionPresence(rolloutCohort: 'beta-a');
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(captured.headers['idempotency-key'], isNotEmpty);
    expect(body['product'], 'caremate');
    expect(body['buildNumber'], '20');
    expect(body['rolloutCohort'], 'beta-a');
    expect(body.containsKey('deviceId'), isFalse);
    expect(body.containsKey('health'), isFalse);
    client.close();
  });
}
