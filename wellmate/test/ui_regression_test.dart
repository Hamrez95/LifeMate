import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:lifemate_ui/lifemate_ui.dart';
import 'package:provider/provider.dart';
import 'package:wellmate/localization/locale_provider.dart';
import 'package:wellmate/main.dart';
import 'package:wellmate/providers/medication_provider.dart';
import 'package:wellmate/providers/notification_provider.dart';
import 'package:wellmate/providers/settings_provider.dart';
import 'package:wellmate/screens/home/active_treatment_card.dart';
import 'package:wellmate/screens/profile/profile_screen.dart';
import 'package:wellmate/screens/treatments/add_treatment_screen.dart';

void main() {
  test('home mounts data-heavy tabs lazily', () {
    final source = File('lib/screens/home/home_screen.dart').readAsStringSync();
    expect(source, contains('final Set<int> _visitedTabs = <int>{5}'));
    expect(source, contains('if (!_visitedTabs.contains(index))'));
    expect(source, contains('_visitedTabs.add(index)'));
  });

  testWidgets('profile route keeps LifeMateApiClient in scope', (
    WidgetTester tester,
  ) async {
    final api = _FakeWellMateApiClient();

    await tester.pumpWidget(
      _wellMateHarness(
        Provider<LifeMateApiClient>.value(
          value: api,
          child: Navigator(
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (context) => Scaffold(
                body: Center(
                  child: FilledButton(
                    key: const Key('open-profile'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ProfileScreen(),
                      ),
                    ),
                    child: const Text('پروفایل'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open-profile')));
    await tester.pumpAndSettle();

    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(find.byType(LifeMateSharedProfileScreen), findsOneWidget);
    expect(find.text('کاربر تست'), findsOneWidget);
    expect(find.byIcon(Icons.camera_alt), findsOneWidget);
    expect(find.byType(LifeMateProfileAvatar), findsWidgets);
    expect(find.text('مدیریت اشتراک‌ها'), findsOneWidget);
    final subscriptionCard = find.byKey(
      const ValueKey('lifemate-subscription-card'),
    );
    expect(subscriptionCard, findsOneWidget);
    expect(
      find.descendant(
        of: subscriptionCard,
        matching: find.text('اشتراکی ندارید'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: subscriptionCard,
        matching: find.text('در دست توسعه'),
      ),
      findsNothing,
    );
    final supplementalActions = find.byKey(
      const ValueKey('profile-supplemental-actions'),
    );
    expect(supplementalActions, findsOneWidget);
    expect(tester.getSize(supplementalActions).height, lessThan(260));
    final avatar = tester.widget<LifeMateProfileAvatar>(
      find.byType(LifeMateProfileAvatar).first,
    );
    expect(
      LifeMateProfileAvatars.normalize(avatar.avatarKey),
      LifeMateProfileAvatars.defaultKey,
    );
    expect(
      find.image(const AssetImage('assets/images/mother_avatar.png')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('add treatment uses one scrollable form without inner tabs', (
    WidgetTester tester,
  ) async {
    final api = _FakeWellMateApiClient();

    await tester.pumpWidget(
      Provider<LifeMateApiClient>.value(
        value: api,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(body: TabbedAddTreatmentScreen(onCreated: () {})),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('wellmate-treatment-single-page-form')),
      findsOneWidget,
    );
    expect(find.text('افزودن درمان'), findsOneWidget);
    expect(
      find.text('همه اطلاعات دارو و برنامه مصرف را در همین صفحه وارد کنید.'),
      findsOneWidget,
    );
    expect(find.byType(TabBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('countdown formatting remains deterministic', () {
    expect(ActiveTreatmentCard.formatCountdown(3661), '1:01:01');
    expect(ActiveTreatmentCard.formatCountdown(61), '01:01');
    expect(ActiveTreatmentCard.formatCountdown(0), 'الان!');
  });

  test('home source retains live and empty countdown UI', () {
    final homeSource = File(
      'lib/screens/home/home_screen_content.dart',
    ).readAsStringSync();
    final cardSource = File(
      'lib/screens/home/active_treatment_card.dart',
    ).readAsStringSync();

    expect(homeSource, contains('ActiveTreatmentCard('));
    expect(homeSource, contains('_TreatmentTimerPlaceholder('));
    expect(homeSource, contains('شروع مراقبت از خودت'));
    expect(homeSource, contains('ثبت اولین برنامه'));
    expect(homeSource, contains("'--:--'"));
    expect(cardSource, contains('CircularProgressIndicator('));
    expect(cardSource, contains('formatCountdown(secondsLeft)'));
  });
}

Widget _wellMateHarness(Widget home) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => NotificationProvider()),
      ChangeNotifierProvider(create: (_) => LocaleProvider()),
      ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ChangeNotifierProvider(create: (_) => MedicationProvider()),
    ],
    child: WellMateApp(home: home),
  );
}

class _FakeWellMateApiClient extends LifeMateApiClient {
  _FakeWellMateApiClient()
    : super(
        baseUri: Uri.parse('https://example.invalid'),
        accessToken: () => 'test-token',
      );

  @override
  Future<Map<String, dynamic>> getCurrentUser() async => {
    'user': {'id': 'patient-1', 'email': 'patient@example.com'},
    'profile': {
      'displayName': 'کاربر تست',
      'email': 'patient@example.com',
      'locale': 'fa',
      'timeZone': 'Asia/Tehran',
    },
  };

  @override
  Future<List<Map<String, dynamic>>> getTreatmentPlans() async => const [];

  @override
  Future<List<Map<String, dynamic>>> getDoseOccurrences({
    required DateTime fromDate,
    required DateTime toDate,
  }) async => const [];
}