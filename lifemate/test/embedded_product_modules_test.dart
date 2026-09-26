import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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
          (call) async => true,
        );
  });

  late LifeMateApiClient apiClient;

  setUp(() {
    apiClient = LifeMateApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'test-session-token',
      httpClient: MockClient((_) async => http.Response('{}', 200)),
    );
  });

  tearDown(() => apiClient.close());

  Future<void> openZone(WidgetTester tester, String zoneId) async {
    await tester.binding.setSurfaceSize(const Size(412, 915));
    await tester.pumpWidget(
      LifeMateApp(
        home: LifeMateShell(
          apiClient: apiClient,
          moduleRegistry: LifeMateModuleRegistry.production(),
          campCompanionSource: const UnavailableCampCompanionSelectionSource(),
        ),
        localeOverride: const Locale('en'),
      ),
    );

    await tester.tap(find.byKey(ValueKey('camp-zone-hit-$zoneId')));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 800));
  }

  testWidgets('WellMate house mounts the shared-session module', (
    tester,
  ) async {
    await openZone(tester, 'wellmate');

    expect(find.byType(WellMateEmbeddedModule), findsOneWidget);
  });

  testWidgets('CareMate house mounts the shared-session module', (
    tester,
  ) async {
    await openZone(tester, 'caremate');

    expect(find.byType(CareMateEmbeddedModule), findsOneWidget);
  });
}

class _NoopFlutterLocalNotificationsPlatform
    extends FlutterLocalNotificationsPlatform {}
