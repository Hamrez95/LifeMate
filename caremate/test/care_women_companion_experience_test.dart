import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import 'package:caremate/screens/women_calendar/care_women_calendar_screen.dart';

void main() {
  testWidgets(
    'spouse dashboard is mobile safe and never renders private notes',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        Provider<LifeMateApiClient>.value(
          value: _FakeCareApi(),
          child: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 800),
              textScaler: TextScaler.linear(1.3),
            ),
            child: const MaterialApp(
              locale: Locale('fa'),
              home: CareWomenCalendarScreen(
                patientUserId: 'patient-1',
                patientName: 'نازنین',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final scrollable = find.byType(Scrollable).first;
      expect(find.text('همدم من'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('care-companion-mobile-dashboard')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await tester.scrollUntilVisible(
        find.text('حال ثبت‌شده همسرم'),
        260,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();
      expect(find.text('حال ثبت‌شده همسرم'), findsOneWidget);
      expect(find.text('حال خوب'), findsOneWidget);
      expect(find.textContaining('انرژی ۴ از ۵'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.scrollUntilVisible(
        find.text('امروز چطور همراه باشم؟'),
        260,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();
      expect(find.text('امروز چطور همراه باشم؟'), findsOneWidget);
      expect(find.textContaining('PRIVATE-NOTE-MUST-NOT-LEAK'), findsNothing);
      expect(find.textContaining('احتمال بارداری'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('revoked women-calendar permission fails closed', (tester) async {
    await tester.pumpWidget(
      Provider<LifeMateApiClient>.value(
        value: _DeniedCareApi(),
        child: const MaterialApp(
          locale: Locale('fa'),
          home: CareWomenCalendarScreen(
            patientUserId: 'patient-1',
            patientName: 'نازنین',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('دسترسی همدم به چرخه فعال نیست یا توسط همسرت متوقف شده است.'),
      findsOneWidget,
    );
    expect(find.text('حال ثبت‌شده همسرم'), findsNothing);
  });
}

class _FakeCareApi extends LifeMateApiClient {
  _FakeCareApi()
    : super(
        baseUri: Uri.parse('https://example.invalid'),
        accessToken: () => 'test-token',
      );

  @override
  Future<Map<String, dynamic>> getCurrentProfile() async => const {
    'displayName': 'حمیدرضا',
    'avatarKey': 'caregiver_teal',
    'profilePhotoUrl': null,
  };

  @override
  Future<Map<String, dynamic>> getCareRecipientWomenCalendar({
    required String patientUserId,
  }) async => const {
    'patient': {'displayName': 'نازنین', 'avatarKey': 'person_pink'},
    'profile': {
      'enabled': true,
      'lastPeriodStart': '2026-08-01',
      'cycleLength': 28,
      'periodLength': 5,
    },
    'estimate': {
      'cycleDay': 5,
      'cycleLength': 28,
      'detailedPhase': 'period',
      'phase': 'period',
      'daysUntilNextPeriod': 23,
      'nextPeriodStart': '2026-08-29',
    },
    'latestSharedDailyLog': {
      'loggedOn': '2026-08-05',
      'mood': 'good',
      'energyLevel': 4,
      'painLevel': 1,
      'symptoms': ['fatigue'],
      'version': 2,
      'updatedAtUtc': '2026-08-05T10:00:00Z',
    },
    'supportActions': [
      {'actionType': 'hydration', 'performedAtUtc': '2026-08-05T09:00:00Z'},
    ],
    'privateNotes': 'PRIVATE-NOTE-MUST-NOT-LEAK',
  };

  @override
  Future<List<Map<String, dynamic>>> getCareRecipientDoseOccurrences({
    required String patientUserId,
    required DateTime fromDate,
    required DateTime toDate,
  }) async => const [
    {
      'id': 'dose-1',
      'medicationName': 'قرص آهن',
      'scheduledLocalTime': '13:00',
      'status': 'missed',
    },
  ];

  @override
  Future<List<Map<String, dynamic>>> getCareRecipientCareEvents({
    required String patientUserId,
    required DateTime fromDate,
    required DateTime toDate,
  }) async => const [
    {
      'id': 'event-1',
      'eventType': 'appointment',
      'title': 'ویزیت دکتر احمدی',
      'scheduledLocalTime': '20:00',
      'status': 'scheduled',
    },
  ];

  @override
  Future<Map<String, dynamic>> recordCareRecipientWomenSupportAction({
    required String patientUserId,
    required String actionType,
  }) async => {
    'id': 'support-2',
    'actionType': actionType,
    'performedAtUtc': '2026-08-05T11:00:00Z',
  };
}

class _DeniedCareApi extends _FakeCareApi {
  @override
  Future<Map<String, dynamic>> getCareRecipientWomenCalendar({
    required String patientUserId,
  }) async {
    throw const LifeMateApiException(
      statusCode: 403,
      code: 'women_calendar_access_denied',
      message: 'Access denied.',
    );
  }
}
