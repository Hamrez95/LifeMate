import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:lifemate_ui/lifemate_ui.dart';

LifeMateApiClient _api() => LifeMateApiClient(
  baseUri: Uri.parse('https://example.test'),
  accessToken: () => 'token',
  httpClient: MockClient((request) async {
    if (request.url.path == '/api/v1/me') {
      return http.Response(
        jsonEncode({
          'user': {'email': 'tester@example.test'},
          'profile': {
            'displayName': 'Test User',
            'phoneNumber': null,
            'avatarKey': null,
            'profilePhotoUrl': null,
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.Response('{}', 200, headers: {'content-type': 'application/json'});
  }),
);

const _theme = LifeMateProfileThemeData(
  background: Color(0xFFF8F7FB),
  accent: Color(0xFF6C63FF),
  titleColor: Color(0xFF222222),
  secondaryText: Color(0xFF777777),
);

const _labels = LifeMateProfileLabels(
  personalInfo: 'Personal info',
  healthProfile: 'Health profile',
  careManagement: 'Care management',
  appSettings: 'Settings',
  referral: 'Referral',
  support: 'Support',
  logout: 'Sign out',
  subscriptionTitle: 'LifeMate Plus',
  manageSubscriptions: 'Manage',
);

Widget _profile({required TextDirection direction}) {
  return MaterialApp(
    home: Directionality(
      textDirection: direction,
      child: MediaQuery(
        data: const MediaQueryData(
          size: Size(360, 800),
          textScaler: TextScaler.linear(1.3),
        ),
        child: LifeMateSharedProfileScreen(
          apiClient: _api(),
          theme: _theme,
          labels: _labels,
          fontFamily: 'Roboto',
          appName: 'WellMate',
          versionLabel: '0.9.0 test',
          fallbackUserName: 'User',
          isPersian: direction == TextDirection.rtl,
          onNotifications: () {},
          onEditProfile: () {},
          onHealthProfile: () {},
          onCareManagement: () {},
          onAppSettings: () {},
          onReferral: () {},
          onSupport: () {},
          onManageSubscriptions: () {},
          feedbackBuilder: (_) => const Scaffold(body: Text('Feedback')),
        ),
      ),
    ),
  );
}

Future<void> _verifyUnifiedProfile(
  WidgetTester tester, {
  required TextDirection direction,
  required String languageCode,
}) async {
  LifeMateRuntimeLocale.setLanguageCode(languageCode);
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(_profile(direction: direction));
  await tester.pumpAndSettle();

  expect(find.byKey(const ValueKey('lifemate-shared-profile-layout')), findsOneWidget);
  expect(find.byKey(const ValueKey('lifemate-shared-profile-scroll')), findsOneWidget);
  expect(find.byType(SingleChildScrollView), findsOneWidget);
  expect(find.byKey(const ValueKey('lifemate-subscription-card')), findsOneWidget);
  expect(tester.takeException(), isNull);

  final scrollable = find.byKey(const ValueKey('lifemate-shared-profile-scroll'));
  for (final key in const [
    ValueKey('profile-feedback'),
    ValueKey('profile-demographics'),
    ValueKey('profile-privacy-preferences'),
  ]) {
    await tester.scrollUntilVisible(
      find.byKey(key),
      240,
      scrollable: scrollable,
    );
    await tester.pump();
    expect(find.byKey(key), findsOneWidget);
    expect(tester.takeException(), isNull);
  }

  final profileContext = tester.element(
    find.byKey(const ValueKey('lifemate-shared-profile-scroll')),
  );
  expect(Directionality.of(profileContext), direction);
}

void main() {
  testWidgets('profile is one scroll surface without overflow on 360x800 RTL', (
    tester,
  ) async {
    await _verifyUnifiedProfile(
      tester,
      direction: TextDirection.rtl,
      languageCode: 'fa',
    );
  });

  testWidgets('profile keeps unified menu and scrolling in LTR', (tester) async {
    await _verifyUnifiedProfile(
      tester,
      direction: TextDirection.ltr,
      languageCode: 'en',
    );
  });
}
