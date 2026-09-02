import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:lifemate_ui/lifemate_ui.dart';

const _subject = '11111111-1111-4111-8111-111111111111';

Map<String, dynamic> _snapshot({
  String updateState = 'current',
  bool womenEnabled = true,
  DateTime? fetchedAt,
}) => {
  'product': 'wellmate',
  'platform': 'android',
  'controls': [
    {
      'key': 'client.women_calendar.enabled',
      'kind': 'FeatureFlag',
      'valueType': 'Boolean',
      'value': womenEnabled,
      'definitionVersion': 1,
      'source': 'rule',
      'ruleVersion': 1,
      'failClosed': true,
    },
  ],
  'updatePolicy': {
    'updateState': updateState,
    'minimumSupportedVersion': updateState == 'force' ? '2.0.0' : null,
    'recommendedVersion': '2.1.0',
    'reasonCode': updateState == 'force' ? 'Security' : 'Routine',
    'messageKey': null,
    'policyVersion': 1,
  },
  'snapshotVersion': 'controls-1:update-1',
  'fetchedAtUtc': (fetchedAt ?? DateTime.now().toUtc()).toIso8601String(),
  'cacheTtlSeconds': 60,
};

LifeMateRemoteConfigClient _client(
  Map<String, dynamic> response, {
  String? cached,
  bool offline = false,
  int failuresBeforeSuccess = 0,
}) {
  var failedRequests = 0;
  return LifeMateRemoteConfigClient(
    baseUri: Uri.parse('https://example.test'),
    product: 'wellmate',
    currentVersion: '1.0.0',
    platform: 'android',
    accessToken: () => 'token',
    cacheSubject: () => _subject,
    cacheRead: (_) async => cached,
    cacheWrite: (_, __) async {},
    httpClient: MockClient((request) async {
      if (request.method == 'POST') return http.Response('{}', 202);
      if (offline) throw http.ClientException('offline');
      if (failedRequests < failuresBeforeSuccess) {
        failedRequests += 1;
        throw http.ClientException('temporary config outage');
      }
      return http.Response(jsonEncode(response), 200);
    }),
  );
}

Widget _app(LifeMateRemoteConfigClient client, {Widget? child}) => MaterialApp(
  home: LifeMateRuntimeConfigGate(
    product: 'wellmate',
    currentVersion: '1.0.0',
    client: client,
    child: child ?? const Text('core-home'),
  ),
);

void main() {
  setUp(() => LifeMateRuntimeLocale.setLanguageCode('en'));

  testWidgets('force update blocks core only for a trusted fresh policy', (
    tester,
  ) async {
    final client = _client(_snapshot(updateState: 'force'));
    await tester.pumpWidget(_app(client));
    await tester.pumpAndSettle();

    expect(find.text('Update required'), findsOneWidget);
    expect(find.text('core-home'), findsNothing);
    client.close();
  });

  testWidgets('stale force cache cannot indefinitely block core care offline', (
    tester,
  ) async {
    final stale = _snapshot(
      updateState: 'force',
      fetchedAt: DateTime.now().toUtc().subtract(const Duration(days: 2)),
    );
    final client = _client(
      _snapshot(),
      cached: jsonEncode(stale),
      offline: true,
    );
    await tester.pumpWidget(_app(client));
    await tester.pumpAndSettle();

    expect(find.text('Update required'), findsNothing);
    expect(find.text('core-home'), findsOneWidget);
    client.close();
  });

  testWidgets('feature guard fails closed when server flag is false', (
    tester,
  ) async {
    final client = _client(_snapshot(womenEnabled: false));
    await tester.pumpWidget(
      _app(
        client,
        child: const LifeMateRemoteFeatureGuard(
          controlKey: 'client.women_calendar.enabled',
          child: Text('women-on'),
          fallback: Text('women-off'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('women-off'), findsOneWidget);
    expect(find.text('women-on'), findsNothing);
    client.close();
  });

  testWidgets('config outage keeps core care available with protected flags off', (
    tester,
  ) async {
    final client = _client(_snapshot(), offline: true);
    await tester.pumpWidget(
      _app(
        client,
        child: const Column(
          children: [
            Text('core-care'),
            LifeMateRemoteFeatureGuard(
              controlKey: 'client.women_calendar.enabled',
              child: Text('protected-on'),
              fallback: Text('protected-off'),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('core-care'), findsOneWidget);
    expect(find.text('protected-off'), findsOneWidget);
    expect(find.text('protected-on'), findsNothing);
    client.close();
  });

  testWidgets('stale runtime-config warning clears after a successful retry', (
    tester,
  ) async {
    final client = _client(_snapshot(), failuresBeforeSuccess: 1);
    await tester.pumpWidget(_app(client));
    await tester.pumpAndSettle();

    const warning =
        'Online config is unavailable; protected features are temporarily disabled.';
    expect(find.text(warning), findsOneWidget);
    expect(find.text('core-home'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text(warning), findsNothing);
    expect(find.text('core-home'), findsOneWidget);
    client.close();
  });
}
