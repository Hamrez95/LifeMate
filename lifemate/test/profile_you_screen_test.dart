import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate/app/lifemate_app.dart';
import 'package:lifemate/modules/module_registry.dart';
import 'package:lifemate/shell/lifemate_shell.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  setUp(LifeMateProfileRefresh.clearCacheForTesting);

  testWidgets('You reuses product profile layout and module sections', (
    tester,
  ) async {
    final api = _profileApi();
    addTearDown(api.close);

    await tester.pumpWidget(
      LifeMateApp(
        home: LifeMateShell(
          apiClient: api,
          moduleRegistry: LifeMateModuleRegistry([
            LifeMateModuleDefinition(
              id: LifeMateModuleId.wellMate,
              routeName: '/modules/wellmate',
              labelEn: 'WellMate',
              labelFa: 'ول‌میت',
              icon: Icons.health_and_safety_outlined,
              availability: ModuleAvailability.available,
              pageBuilder: (_, __, ___) => const SizedBox.shrink(),
              profileSectionsBuilder: (_, client, isPersian) => [
                Card(
                  child: Text(
                    identical(client, api) && !isPersian
                        ? 'WellMate settings'
                        : 'Wrong profile context',
                  ),
                ),
              ],
            ),
          ]),
        ),
        localeOverride: const Locale('en'),
      ),
    );

    await tester.tap(find.byTooltip('Open profile'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('lifemate-shared-profile-layout')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('lifemate-subscription-card')),
      findsOneWidget,
    );
    expect(find.text('Personal information'), findsOneWidget);
    expect(find.text('Health profile'), findsOneWidget);
    expect(find.text('Care management'), findsOneWidget);
    expect(find.text('WellMate settings'), findsOneWidget);
    expect(find.byKey(const ValueKey('lifemate-data-export')), findsOneWidget);
    expect(find.text('Ambient audio'), findsNothing);

    final directionality = tester.widget<Directionality>(
      find.byType(Directionality).first,
    );
    expect(directionality.textDirection, TextDirection.ltr);
  });

  testWidgets('changing shell profile language updates copy and direction', (
    tester,
  ) async {
    final api = _profileApi();
    addTearDown(api.close);

    await tester.pumpWidget(_LocalizedShellHarness(api));

    await tester.tap(find.byTooltip('Open profile'));
    await tester.pumpAndSettle();
    expect(find.text('Personal information'), findsOneWidget);
    expect(
      tester
          .widget<Directionality>(find.byType(Directionality).first)
          .textDirection,
      TextDirection.ltr,
    );

    await tester.tap(find.text('App settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(RadioListTile<String>).first);
    await tester.pumpAndSettle();

    expect(find.text('اطلاعات شخصی'), findsOneWidget);
    expect(find.text('پرونده سلامت'), findsOneWidget);
    expect(LifeMateRuntimeLocale.languageCode, 'fa');
    expect(
      tester
          .widget<Directionality>(find.byType(Directionality).first)
          .textDirection,
      TextDirection.rtl,
    );

    await tester.tap(find.text('تنظیمات برنامه'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(RadioListTile<String>).last);
    await tester.pumpAndSettle();

    expect(find.text('Personal information'), findsOneWidget);
    expect(find.text('اطلاعات شخصی'), findsNothing);
    expect(LifeMateRuntimeLocale.languageCode, 'en');
    expect(
      tester
          .widget<Directionality>(find.byType(Directionality).first)
          .textDirection,
      TextDirection.ltr,
    );
  });

  testWidgets('shared editor applies its saved language to the shell', (
    tester,
  ) async {
    final api = _profileApi();
    addTearDown(api.close);

    await tester.pumpWidget(_LocalizedShellHarness(api));
    await tester.tap(find.byTooltip('Open profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Personal information'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('lifemate-account-security')),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Persian'));
    await tester.tap(find.text('Persian'));
    await tester.pumpAndSettle();
    final save = find.byKey(const ValueKey('lifemate-profile-save'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(LifeMateRuntimeLocale.languageCode, 'fa');
    expect(
      tester
          .widget<Directionality>(find.byType(Directionality).first)
          .textDirection,
      TextDirection.rtl,
    );
  });
}

class _LocalizedShellHarness extends StatefulWidget {
  const _LocalizedShellHarness(this.apiClient);

  final LifeMateApiClient apiClient;

  @override
  State<_LocalizedShellHarness> createState() => _LocalizedShellHarnessState();
}

class _LocalizedShellHarnessState extends State<_LocalizedShellHarness> {
  Locale _locale = const Locale('en');

  @override
  Widget build(BuildContext context) => LifeMateApp(
    localeOverride: _locale,
    home: LifeMateShell(
      apiClient: widget.apiClient,
      onLocaleChanged: (locale) {
        LifeMateRuntimeLocale.setLanguageCode(locale.languageCode);
        setState(() => _locale = locale);
      },
    ),
  );
}

LifeMateApiClient _profileApi() {
  var profile = <String, dynamic>{
    'id': 'profile-1',
    'userId': 'user-1',
    'displayName': 'Hamid',
    'phoneNumber': null,
    'email': 'owner@example.test',
    'locale': 'en',
    'timeZone': 'Europe/Berlin',
    'avatarKey': 'person_green',
    'profilePhotoUrl': null,
    'version': 3,
  };

  return LifeMateApiClient(
    baseUri: Uri.parse('https://api.example.test'),
    accessToken: () => 'test-token',
    httpClient: MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/api/v1/me') {
        return http.Response(
          jsonEncode({
            'user': {'id': 'user-1', 'email': 'owner@example.test'},
            'profile': profile,
          }),
          200,
        );
      }
      if (request.method == 'GET' && request.url.path == '/api/v1/me/profile') {
        return http.Response(jsonEncode(profile), 200);
      }
      if (request.method == 'PATCH' &&
          request.url.path == '/api/v1/me/profile') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        profile = <String, dynamic>{...profile, ...body, 'version': 4};
        return http.Response(jsonEncode(profile), 200);
      }
      return http.Response('{}', 404);
    }),
  );
}
