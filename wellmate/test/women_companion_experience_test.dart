import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';
import 'package:wellmate/screens/women_calendar/women_companion_screen.dart';

void main() {
  testWidgets(
    'women companion dashboard is mobile safe and excludes pregnancy features',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        Provider<LifeMateApiClient>.value(
          value: _FakeLifeMateApiClient(),
          child: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 800),
              textScaler: TextScaler.linear(1.3),
            ),
            child: MaterialApp(
              locale: const Locale('fa'),
              home: Scaffold(
                body: WomenCompanionScreen(
                  companionApi: _FakeWomenCompanionApi(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final dashboard = find.byKey(
        const ValueKey('women-companion-mobile-dashboard'),
      );
      expect(dashboard, findsOneWidget);
      expect(find.text('فاز قاعدگی'), findsOneWidget);
      expect(tester.takeException(), isNull);

      for (final title in const [
        'حال و احساس امروز',
        'نکته امروز',
        '۱۴ روز پیش رو',
        'گزارش‌های من',
      ]) {
        await tester.scrollUntilVisible(
          find.text(title),
          260,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(find.text(title), findsOneWidget);
        final exception = tester.takeException();
        expect(exception, isNull, reason: 'overflow after $title');
      }

      expect(find.textContaining('احتمال بارداری'), findsNothing);
      expect(find.textContaining('اقدام به بارداری'), findsNothing);
    },
    skip: !LifeMateFeatureFlags.womenCalendarPilotEnabled,
  );

  testWidgets(
    'daily check-in explains consent and private-note boundary',
    (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        Provider<LifeMateApiClient>.value(
          value: _FakeLifeMateApiClient(),
          child: MaterialApp(
            locale: const Locale('fa'),
            home: Scaffold(
              body: WomenCompanionScreen(
                companionApi: _FakeWomenCompanionApi(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('ویرایش'),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('ویرایش'));
      await tester.pumpAndSettle();

      expect(find.text('یادداشت خصوصی'), findsOneWidget);
      expect(find.text('اشتراک خلاصه با همدم'), findsOneWidget);
      expect(
        find.textContaining('یادداشت خصوصی هرگز به اشتراک گذاشته نمی‌شود'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
    skip: !LifeMateFeatureFlags.womenCalendarPilotEnabled,
  );
}

class _FakeLifeMateApiClient extends LifeMateApiClient {
  _FakeLifeMateApiClient()
    : super(
        baseUri: Uri.parse('https://example.invalid'),
        accessToken: () => 'test-token',
      );

  @override
  Future<Map<String, dynamic>> getWomenCalendarProfile() async => {
    'enabled': true,
    'lastPeriodStart': '2026-08-01',
    'cycleLength': 28,
    'periodLength': 5,
    'remindersEnabled': true,
    'version': 2,
  };

  @override
  Future<List<Map<String, dynamic>>> getWomenCalendarEpisodes() async => [
    {
      'id': 'episode-1',
      'startedOn': '2026-08-01',
      'endedOn': '2026-08-05',
      'version': 1,
    },
  ];

  @override
  Future<Map<String, dynamic>> getCurrentProfile() async => const {
    'displayName': 'نازنین',
    'avatarKey': 'person_pink',
    'profilePhotoUrl': null,
  };

  @override
  Future<List<Map<String, dynamic>>> getCareRelationships() async => [
    {
      'id': 'relationship-1',
      'status': 'active',
      'caregiverDisplayName': 'حمیدرضا',
      'canViewWomenCalendar': true,
    },
  ];
}

class _FakeWomenCompanionApi extends WomenCompanionApi {
  _FakeWomenCompanionApi()
    : super(
        baseUri: Uri.parse('https://example.invalid'),
        accessToken: () => 'test-token',
      );

  @override
  Future<List<Map<String, dynamic>>> getDailyLogs({
    required DateTime fromDate,
    required DateTime toDate,
  }) async => [
    {
      'id': 'daily-1',
      'loggedOn': '2026-08-05',
      'mood': 'good',
      'energyLevel': 4,
      'painLevel': 1,
      'symptoms': ['fatigue'],
      'privateNotes': 'private owner note',
      'shareSummaryWithCompanion': true,
      'version': 1,
    },
  ];

  @override
  Future<Map<String, dynamic>> saveDailyLog({
    required int version,
    required DateTime loggedOn,
    required String mood,
    required int energyLevel,
    required int painLevel,
    required List<String> symptoms,
    String? privateNotes,
    required bool shareSummaryWithCompanion,
  }) async => {
    'id': 'daily-1',
    'loggedOn': '2026-08-05',
    'mood': mood,
    'energyLevel': energyLevel,
    'painLevel': painLevel,
    'symptoms': symptoms,
    'privateNotes': privateNotes,
    'shareSummaryWithCompanion': shareSummaryWithCompanion,
    'version': version + 1,
  };
}
