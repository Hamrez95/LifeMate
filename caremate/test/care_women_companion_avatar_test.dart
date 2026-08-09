import 'package:caremate/screens/women_calendar/care_women_calendar_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

void main() {
  setUp(LifeMateProfileRefresh.clearCacheForTesting);
  tearDown(LifeMateProfileRefresh.clearCacheForTesting);

  testWidgets(
    'caregiver women calendar uses patient relationship photo and own profile',
    (tester) async {
      tester.view.physicalSize = const Size(390, 820);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final api = _CareWomenAvatarApi();
      await tester.pumpWidget(
        Provider<LifeMateApiClient>.value(
          value: api,
          child: const MaterialApp(
            locale: Locale('fa'),
            home: CareWomenCalendarScreen(
              patientUserId: 'reyhaneh-user',
              patientName: 'ریحانه',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final patientAvatar = tester.widget<LifeMateProfileAvatar>(
        find.byKey(const ValueKey('care-women-patient-avatar')),
      );
      expect(
        patientAvatar.photoUrl,
        'https://example.invalid/reyhaneh-signed.jpg',
      );
      expect(patientAvatar.avatarKey, 'person_purple');

      expect(
        find.byKey(const ValueKey('care-women-current-caregiver-avatar')),
        findsOneWidget,
      );
      final cachedCaregiver = LifeMateProfileRefresh.peek(api);
      expect(cachedCaregiver?['displayName'], 'حمید ۲');
      expect(cachedCaregiver?['profilePhotoUrl'], isNull);
      expect(tester.takeException(), isNull);
    },
  );
}

class _CareWomenAvatarApi extends LifeMateApiClient {
  _CareWomenAvatarApi()
    : super(
        baseUri: Uri.parse('https://example.invalid'),
        accessToken: () => 'test-token',
      );

  @override
  Future<Map<String, dynamic>> getCurrentProfile() async => const {
    'displayName': 'حمید ۲',
    'avatarKey': 'person_blue',
    'profilePhotoUrl': null,
  };

  @override
  Future<List<Map<String, dynamic>>> getCareRelationships() async => const [
    {
      'id': 'relationship-hamid-2',
      'status': 'active',
      'patientUserId': 'reyhaneh-user',
      'caregiverUserId': 'hamid-2',
      'patientDisplayName': 'ریحانه',
      'patientAvatarKey': 'person_purple',
      'patientProfilePhotoUrl': 'https://example.invalid/reyhaneh-signed.jpg',
      'canViewWomenCalendar': true,
    },
  ];

  @override
  Future<Map<String, dynamic>> getCareRecipientWomenCalendar({
    required String patientUserId,
  }) async => const {
    'patient': {'displayName': 'ریحانه', 'avatarKey': 'person_purple'},
    'profile': {
      'enabled': true,
      'lastPeriodStart': '2026-08-08',
      'cycleLength': 28,
      'periodLength': 5,
    },
    'estimate': {
      'cycleDay': 2,
      'cycleLength': 28,
      'detailedPhase': 'period',
      'phase': 'period',
      'daysUntilNextPeriod': 26,
      'nextPeriodStart': '2026-09-05',
    },
    'latestSharedDailyLog': null,
    'supportActions': [],
  };

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
}
