import 'package:caremate/core/localization/locale_provider.dart';
import 'package:caremate/main.dart';
import 'package:caremate/screens/feature_preview_screen.dart';
import 'package:caremate/screens/profile_destination_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('CareMate app shell builds with its root provider',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => LocaleProvider(),
        child: const CareMateApp(home: SizedBox.shrink()),
      ),
    );

    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(CareMateApp), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('CareMate connected destinations render real empty states',
      (WidgetTester tester) async {
    final api = _FakeCareMateApiClient();

    Future<void> pump(Widget destination) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<LifeMateApiClient>.value(value: api),
            ChangeNotifierProvider(create: (_) => LocaleProvider()),
          ],
          child: MaterialApp(home: destination),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    await pump(const CareMatePersonalInformationScreen());
    expect(find.text('مراقب تست'), findsOneWidget);
    expect(find.text('caregiver@example.com'), findsOneWidget);

    await pump(const CareMateNotificationsScreen());
    expect(find.text('فردی به CareMate متصل نیست'), findsOneWidget);

    await pump(const CareMateFeaturePreviewScreen(initialIndex: 2));
    expect(find.text('هنوز فردی برای مراقبت متصل نشده است.'), findsOneWidget);
  });

  testWidgets('CareMate unsupported destinations remain complete pages',
      (WidgetTester tester) async {
    Future<void> pump(Widget destination, String expectedText) async {
      await tester.pumpWidget(MaterialApp(home: destination));
      await tester.pumpAndSettle();
      expect(find.text(expectedText), findsWidgets);
      expect(tester.takeException(), isNull);
    }

    await pump(const CareMateReferralScreen(), 'کد معرف');
    await pump(const CareMateSupportScreen(), 'پشتیبانی');
    await pump(const CareMateSubscriptionScreen(), 'اشتراک CareMate');
  });
}

class _FakeCareMateApiClient extends LifeMateApiClient {
  _FakeCareMateApiClient()
      : super(
          baseUri: Uri.parse('https://example.invalid'),
          accessToken: () => 'test-token',
        );

  @override
  Future<Map<String, dynamic>> getCurrentUser() async => {
        'user': {
          'id': 'caregiver-1',
          'email': 'caregiver@example.com',
        },
        'profile': {
          'displayName': 'مراقب تست',
          'locale': 'fa',
          'timeZone': 'Asia/Tehran',
        },
      };

  @override
  Future<List<Map<String, dynamic>>> getCareRelationships() async => const [];

  @override
  Future<List<Map<String, dynamic>>> getCareRecipientDoseOccurrences({
    required String patientUserId,
    required DateTime fromDate,
    required DateTime toDate,
  }) async => const [];
}
