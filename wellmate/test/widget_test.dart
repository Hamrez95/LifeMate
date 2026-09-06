import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';
import 'package:wellmate/localization/locale_provider.dart';
import 'package:wellmate/main.dart';
import 'package:wellmate/providers/medication_provider.dart';
import 'package:wellmate/providers/notification_provider.dart';
import 'package:wellmate/providers/settings_provider.dart';
import 'package:wellmate/screens/profile/profile_destination_screens.dart';

void main() {
  testWidgets('WellMate app shell builds with its root providers', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => NotificationProvider()),
          ChangeNotifierProvider(create: (_) => LocaleProvider()),
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
          ChangeNotifierProvider(create: (_) => MedicationProvider()),
        ],
        child: const WellMateApp(home: SizedBox.shrink()),
      ),
    );

    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(WellMateApp), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('WellMate live profile destinations render without mock data', (
    WidgetTester tester,
  ) async {
    final api = _FakeLifeMateApiClient();

    Future<void> pump(Widget destination) async {
      await tester.pumpWidget(
        Provider<LifeMateApiClient>.value(
          value: api,
          child: MaterialApp(home: destination),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    await pump(const PersonalInformationScreen());
    expect(find.text('کاربر تست'), findsOneWidget);
    expect(find.text('patient@example.com'), findsOneWidget);

    await pump(const HealthRecordScreen());
    expect(find.text('پرونده سلامت'), findsOneWidget);

    await pump(const NotificationCenterScreen());
    expect(find.text('برای امروز یادآوری دارویی وجود ندارد.'), findsOneWidget);
  });

  testWidgets('WellMate unsupported destinations remain complete pages', (
    WidgetTester tester,
  ) async {
    Future<void> pump(Widget destination, String expectedText) async {
      await tester.pumpWidget(MaterialApp(home: destination));
      await tester.pumpAndSettle();
      expect(find.text(expectedText), findsWidgets);
      expect(tester.takeException(), isNull);
    }

    await pump(const ReferralScreen(), 'کد معرف');
    await pump(const SupportScreen(), 'پشتیبانی');
    await pump(const SubscriptionScreen(), 'اشتراک LifeMate');
  });
}

class _FakeLifeMateApiClient extends LifeMateApiClient {
  _FakeLifeMateApiClient()
    : super(
        baseUri: Uri.parse('https://example.invalid'),
        accessToken: () => 'test-token',
      );

  @override
  Future<Map<String, dynamic>> getCurrentUser() async => {
    'user': {'id': 'patient-1', 'email': 'patient@example.com'},
    'profile': {
      'displayName': 'کاربر تست',
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
