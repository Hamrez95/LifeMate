import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:caremate/screens/caremate_root_shell.dart';
import 'package:wellmate/main.dart' show WellMateEmbeddedModule;
import 'package:caremate/main.dart' show CareMateEmbeddedModule;
import 'package:lifemate/app/lifemate_app.dart';
import 'package:lifemate/circle/camp_companion_selection.dart';
import 'package:lifemate/modules/module_registry.dart';
import 'package:lifemate/shell/lifemate_shell.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  setUpAll(() {
    FlutterLocalNotificationsPlatform.instance =
        _NoopFlutterLocalNotificationsPlatform();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('home_widget'),
          (call) async => switch (call.method) {
            'getInstalledWidgets' => <Object?>[],
            'saveWidgetData' => true,
            _ => null,
          },
        );
  });

  late LifeMateApiClient apiClient;
  final remoteConfigClients = <String, LifeMateRemoteConfigClient>{};

  final testConfig = const AppConfig(
    supabaseUrl: 'https://supabase.example.test',
    supabasePublishableKey: 'sb_publishable_test_key',
    apiBaseUrl: 'https://api.example.test',
  );

  setUp(() {
    apiClient = LifeMateApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'test-session-token',
      httpClient: MockClient(
        (_) async => http.Response('{"code":"session_invalid"}', 401),
      ),
    );
  });

  tearDown(() {
    apiClient.close();
    for (final client in remoteConfigClients.values) {
      client.close();
    }
    remoteConfigClients.clear();
  });

  Future<void> openZone(WidgetTester tester, String zoneId) async {
    await tester.binding.setSurfaceSize(const Size(412, 915));
    await tester.pumpWidget(
      LifeMateApp(
        home: LifeMateShell(
          apiClient: apiClient,
          moduleRegistry: LifeMateModuleRegistry.production(
            config: testConfig,
            remoteConfigClientBuilder: (product) => remoteConfigClients
                .putIfAbsent(product, () => _remoteConfigClient(product)),
            companionCareApiBuilder: _companionCareApi,
          ),
          campCompanionSource: const UnavailableCampCompanionSelectionSource(),
        ),
        localeOverride: const Locale('en'),
      ),
    );

    await tester.tap(find.byKey(ValueKey('camp-zone-hit-$zoneId')));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 800));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }

  testWidgets('WellMate house opens its authenticated product home', (
    tester,
  ) async {
    await openZone(tester, 'wellmate');

    expect(find.byType(WellMateEmbeddedModule), findsOneWidget);
    expect(find.text('Sign in'), findsNothing);
    expect(find.textContaining('This module is not mounted'), findsNothing);
  });

  testWidgets('CareMate house opens its authenticated product dashboard', (
    tester,
  ) async {
    await openZone(tester, 'caremate');

    expect(find.byType(CareMateEmbeddedModule), findsOneWidget);
    expect(find.byType(CareMateRootShell), findsOneWidget);
    expect(find.text('Sign in'), findsNothing);
    expect(find.textContaining('This module is not mounted'), findsNothing);
  });
}

LifeMateRemoteConfigClient _remoteConfigClient(String product) =>
    LifeMateRemoteConfigClient(
      baseUri: Uri.parse('https://api.example.test'),
      product: product,
      currentVersion: '0.0.0-test',
      platform: 'test',
      accessToken: () => 'test-session-token',
      cacheSubject: () => '11111111-1111-4111-8111-111111111111',
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'product': product,
            'platform': 'test',
            'controls': const <Object>[],
            'updatePolicy': {'updateState': 'current', 'policyVersion': 1},
            'snapshotVersion': 'test-v1',
            'fetchedAtUtc': DateTime.now().toUtc().toIso8601String(),
            'cacheTtlSeconds': 60,
          }),
          200,
        ),
      ),
      cacheRead: (_) async => null,
      cacheWrite: (_, __) async {},
    );

LifeMateCompanionCareApi _companionCareApi() => LifeMateCompanionCareApi(
  baseUri: Uri.parse('https://api.example.test'),
  accessToken: () => 'test-session-token',
  httpClient: MockClient(
    (_) async => http.Response('{"code":"test_unavailable"}', 503),
  ),
);

class _NoopFlutterLocalNotificationsPlatform
    extends FlutterLocalNotificationsPlatform {}
