import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';
import 'package:wellmate/localization/locale_provider.dart';
import 'package:wellmate/main.dart';
import 'package:wellmate/providers/medication_provider.dart';
import 'package:wellmate/providers/notification_provider.dart';
import 'package:wellmate/providers/settings_provider.dart';
import 'package:wellmate/screens/home/home_screen_content.dart';
import 'package:wellmate/screens/profile/profile_screen.dart';
import 'package:wellmate/screens/treatments/add_treatment_screen.dart';

void main() {
  testWidgets('profile route keeps LifeMateApiClient in scope',
      (WidgetTester tester) async {
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
    expect(find.text('کاربر تست'), findsOneWidget);
    expect(find.byIcon(Icons.camera_alt), findsOneWidget);
    final avatar = tester.widget<CircleAvatar>(
      find.byType(CircleAvatar).first,
    );
    expect(
      avatar.backgroundImage,
      isA<AssetImage>().having(
        (image) => image.assetName,
        'assetName',
        'assets/images/mother_avatar.png',
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('add treatment retains medicine schedule and review tabs',
      (WidgetTester tester) async {
    final api = _FakeWellMateApiClient();

    await tester.pumpWidget(
      Provider<LifeMateApiClient>.value(
        value: api,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: TabbedAddTreatmentScreen(onCreated: () {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('دارو'), findsOneWidget);
    expect(find.text('برنامه'), findsOneWidget);
    expect(find.text('مرور'), findsOneWidget);
    expect(find.text('افزودن دارو و برنامه درمان'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home keeps the timer card visible without a treatment',
      (WidgetTester tester) async {
    final api = _FakeWellMateApiClient();

    await tester.pumpWidget(
      _wellMateHarness(
        Provider<LifeMateApiClient>.value(
          value: api,
          child: Scaffold(
            body: HomeScreenContent(
              onOpenTreatments: () {},
              onAddTreatment: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 50));

    expect(find.text('تایمر درمان آماده است'), findsOneWidget);
    expect(find.text('--:--'), findsOneWidget);
    expect(find.text('افزودن درمان'), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
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
        'user': {
          'id': 'patient-1',
          'email': 'patient@example.com',
        },
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
