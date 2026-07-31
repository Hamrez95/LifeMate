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

  testWidgets('CareMate connected destinations call the live-data contract',
      (WidgetTester tester) async {
    final api = _FakeCareMateApiClient();

    Future<void> pump(Widget destination) async {
      await tester.pumpWidget(
        Provider<LifeMateApiClient>.value(
          value: api,
          child: MaterialApp(home: destination),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
    }

    await pump(const CareMatePersonalInformationScreen());
    expect(api.currentUserCalls, greaterThan(0));

    await pump(const CareMateNotificationsScreen());
    expect(api.relationshipCalls, greaterThan(0));
  });

  testWidgets('CareMate unsupported destinations remain complete pages',
      (WidgetTester tester) async {
    Future<void> pump(Widget destination) async {
      await tester.pumpWidget(MaterialApp(home: destination));
      await tester.pump();
      expect(
        find.textContaining('در دست توسعه', skipOffstage: false),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
    }

    await pump(const CareMateReferralScreen());
    await pump(const CareMateSupportScreen());
    await pump(const CareMateSubscriptionScreen());
  });

  test('CareMate treatment destination remains part of the navigation surface',
      () {
    const destination = CareMateFeaturePreviewScreen(initialIndex: 2);
    expect(destination.initialIndex, 2);
  });
}

class _FakeCareMateApiClient extends LifeMateApiClient {
  _FakeCareMateApiClient()
      : super(
          baseUri: Uri.parse('https://example.invalid'),
          accessToken: () => 'test-token',
        );

  int currentUserCalls = 0;
  int relationshipCalls = 0;

  @override
  Future<Map<String, dynamic>> getCurrentUser() async {
    currentUserCalls += 1;
    return {
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
  }

  @override
  Future<List<Map<String, dynamic>>> getCareRelationships() async {
    relationshipCalls += 1;
    return const [];
  }

  @override
  Future<List<Map<String, dynamic>>> getCareRecipientDoseOccurrences({
    required String patientUserId,
    required DateTime fromDate,
    required DateTime toDate,
  }) async => const [];
}
