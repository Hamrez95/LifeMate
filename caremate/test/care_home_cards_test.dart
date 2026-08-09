import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import 'package:caremate/core/localization/locale_provider.dart';
import 'package:caremate/main.dart';
import 'package:caremate/models/care_home_snapshot.dart';
import 'package:caremate/providers/care_notification_provider.dart';
import 'package:caremate/screens/dashboard_screen.dart';
import 'package:caremate/screens/women_calendar/care_women_calendar_screen.dart';
import 'package:caremate/widgets/care_home_cards.dart';

void main() {
  testWidgets('queue keeps current/next structure for one and zero events', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fa'),
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              CareHomeTreatmentQueueCard(
                current: _item('one', hour: 10),
                next: null,
                isPersian: true,
                font: const TextStyle(fontFamily: 'Vazir'),
              ),
              const SizedBox(height: 20),
              const CareHomeTreatmentQueueCard(
                current: null,
                next: null,
                isPersian: true,
                font: TextStyle(fontFamily: 'Vazir'),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('درمان فعلی'), findsNWidgets(2));
    expect(find.text('درمان بعدی'), findsNWidgets(2));
    expect(find.text('درمان بعدی ثبت نشده است.'), findsOneWidget);
    expect(find.text('درمان برنامه‌ریزی‌شده‌ای در صف نیست.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('queue passes signed profile photo and avatar fallback metadata', (tester) async {
    const signedUrl = 'https://example.invalid/signed-profile.webp';
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fa'),
        home: Scaffold(
          body: CareHomeTreatmentQueueCard(
            current: _item(
              'photo',
              hour: 10,
              photoUrl: signedUrl,
              avatarKey: 'person_green',
            ),
            next: _item(
              'fallback',
              hour: 11,
              avatarKey: 'person_purple',
            ),
            isPersian: true,
            font: const TextStyle(fontFamily: 'Vazir'),
          ),
        ),
      ),
    );

    final avatars = tester.widgetList<LifeMateProfileAvatar>(
      find.byType(LifeMateProfileAvatar),
    ).toList(growable: false);
    expect(avatars, hasLength(2));
    expect(avatars.first.photoUrl, signedUrl);
    expect(avatars.first.avatarKey, 'person_green');
    expect(avatars.last.photoUrl, isNull);
    expect(avatars.last.avatarKey, 'person_purple');
  });

  testWidgets('companion card is permission safe and child remains a preview', (tester) async {
    var taps = 0;
    const relationship = CareHomeRelationship(
      relationshipId: 'rel-1',
      patientUserId: 'patient-1',
      patientDisplayName: 'ریحانه',
      canViewWomenCalendar: true,
    );
    final shared = CareCompanionHomeSummary.fromApi(
      relationship: relationship,
      value: const {
        'estimate': {'cycleDay': 12, 'cycleLength': 28},
        'latestSharedDailyLog': {'mood': 'good', 'energyLevel': 4},
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fa'),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                const Expanded(
                  child: CareHomeChildPreviewCard(
                    font: TextStyle(fontFamily: 'Vazir'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: CareHomeCompanionCard(
                    summary: shared,
                    isPersian: true,
                    font: const TextStyle(fontFamily: 'Vazir'),
                    onTap: () => taps += 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('به زودی'), findsOneWidget);
    expect(find.textContaining('حال همدم: خوب'), findsOneWidget);
    await tester.tap(find.text('وضعیت همدم'));
    await tester.pump();
    expect(taps, 1);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      MaterialApp(
        home: CareHomeCompanionCard(
          summary: CareCompanionHomeSummary.locked(),
          isPersian: true,
          font: const TextStyle(fontFamily: 'Vazir'),
        ),
      ),
    );
    expect(find.text('دسترسی اشتراک تقویم فعال نیست'), findsOneWidget);
    expect(find.textContaining('حال همدم:'), findsNothing);
  });

  testWidgets('home companion card opens the existing women-calendar route', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<LifeMateApiClient>.value(value: _HomeApi()),
          ChangeNotifierProvider(create: (_) => LocaleProvider()),
          ChangeNotifierProvider(create: (_) => CareNotificationProvider()),
        ],
        child: const CareMateApp(home: DashboardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('care-home-global-dashboard')), findsOneWidget);
    expect(find.text('وضعیت همدم'), findsOneWidget);
    await tester.tap(find.text('وضعیت همدم'));
    await tester.pumpAndSettle();

    expect(find.byType(CareWomenCalendarScreen), findsOneWidget);
    expect(find.text('همدم من'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final width in <double>[360, 390, 412, 430]) {
    testWidgets('status cards stay overflow-free at ${width.toInt()}px and 1.25x text', (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
            size: Size(width, 800),
            textScaler: const TextScaler.linear(1.25),
          ),
          child: MaterialApp(
            locale: const Locale('fa'),
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    const Expanded(
                      child: CareHomeCompanionCard(
                        summary: CareCompanionHomeSummary(
                          hasPermission: false,
                          available: false,
                        ),
                        isPersian: true,
                        font: TextStyle(fontFamily: 'Vazir'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: CareHomeChildPreviewCard(
                        font: TextStyle(fontFamily: 'Vazir'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}

CareHomeTreatmentItem _item(
  String id, {
  required int hour,
  String? photoUrl,
  String? avatarKey,
}) => CareHomeTreatmentItem(
  relationshipId: 'rel-1',
  patientUserId: 'patient-1',
  patientDisplayName: 'ریحانه',
  patientProfilePhotoUrl: photoUrl,
  patientAvatarKey: avatarKey ?? 'person_purple',
  type: CareItemType.injection,
  treatmentId: 'series-$id',
  occurrenceId: id,
  title: 'ویتامین B12',
  subtitle: 'عضلانی',
  scheduledAt: DateTime(2026, 8, 9, hour),
  scheduledLocalTime: '${hour.toString().padLeft(2, '0')}:00',
  status: 'scheduled',
  raw: const {},
);

class _HomeApi extends LifeMateApiClient {
  _HomeApi()
    : super(
        baseUri: Uri.parse('https://example.invalid'),
        accessToken: () => 'token',
      );

  @override
  Future<Map<String, dynamic>> getCurrentUser() async => const {
    'user': {'id': 'caregiver'},
    'profile': {'timeZone': 'Asia/Tehran'},
  };

  @override
  Future<Map<String, dynamic>> getCurrentProfile() async => const {
    'displayName': 'مراقب',
    'avatarKey': 'caregiver_teal',
    'profilePhotoUrl': null,
  };

  @override
  Future<List<Map<String, dynamic>>> getCareRelationships() async => const [
    {
      'id': 'rel-1',
      'patientUserId': 'patient-1',
      'patientDisplayName': 'ریحانه',
      'patientAvatarKey': 'person_purple',
      'caregiverUserId': 'caregiver',
      'status': 'active',
      'canViewWomenCalendar': true,
    },
  ];

  @override
  Future<List<Map<String, dynamic>>> getCareRecipientDoseOccurrences({
    required String patientUserId,
    required DateTime fromDate,
    required DateTime toDate,
  }) async => const [];

  @override
  Future<List<Map<String, dynamic>>> getCareRecipientCareEvents({
    required String patientUserId,
    required DateTime fromDate,
    required DateTime toDate,
  }) async => const [];

  @override
  Future<Map<String, dynamic>> getCareRecipientWomenCalendar({
    required String patientUserId,
  }) async => const {
    'patient': {'displayName': 'ریحانه', 'avatarKey': 'person_purple'},
    'profile': {
      'enabled': true,
      'lastPeriodStart': '2026-08-01',
      'cycleLength': 28,
      'periodLength': 5,
    },
    'estimate': {
      'cycleDay': 12,
      'cycleLength': 28,
      'detailedPhase': 'follicular',
      'daysUntilNextPeriod': 16,
    },
    'latestSharedDailyLog': {
      'mood': 'good',
      'energyLevel': 4,
      'painLevel': 1,
      'symptoms': <String>[],
    },
    'supportActions': <Map<String, dynamic>>[],
  };

  @override
  Future<Map<String, dynamic>> recordCareRecipientWomenSupportAction({
    required String patientUserId,
    required String actionType,
  }) async => {
    'id': 'action-1',
    'actionType': actionType,
    'performedAtUtc': '2026-08-09T10:00:00Z',
  };
}
