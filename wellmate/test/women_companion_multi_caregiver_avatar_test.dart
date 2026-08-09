import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';
import 'package:wellmate/screens/women_calendar/women_companion_screen.dart';

void main() {
  testWidgets(
    'women calendar keeps owner avatar and renders every permitted caregiver',
    (tester) async {
      tester.view.physicalSize = const Size(390, 820);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        Provider<LifeMateApiClient>.value(
          value: _MultiCaregiverApi(),
          child: MaterialApp(
            locale: const Locale('fa'),
            home: Scaffold(
              body: WomenCompanionScreen(
                companionApi: _NoopWomenCompanionApi(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final owner = tester.widget<LifeMateProfileAvatar>(
        find.byKey(const ValueKey('women-companion-owner-avatar')),
      );
      expect(owner.photoUrl, 'https://example.invalid/reyhaneh.jpg');
      expect(owner.avatarKey, 'person_purple');

      final hamid1 = tester.widget<LifeMateProfileAvatar>(
        find.byKey(
          const ValueKey(
            'women-companion-caregiver-avatar-relationship-hamid-1',
          ),
        ),
      );
      expect(hamid1.photoUrl, 'https://example.invalid/hamid1.jpg');
      expect(hamid1.avatarKey, 'person_green');

      final hamid2 = tester.widget<LifeMateProfileAvatar>(
        find.byKey(
          const ValueKey(
            'women-companion-caregiver-avatar-relationship-hamid-2',
          ),
        ),
      );
      expect(hamid2.photoUrl, isNull);
      expect(hamid2.avatarKey, 'person_blue');

      expect(
        find.byKey(
          const ValueKey(
            'women-companion-caregiver-avatar-relationship-no-calendar',
          ),
        ),
        findsNothing,
      );
      expect(find.text('۲ مراقب'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    skip: !LifeMateFeatureFlags.womenCalendarPilotEnabled,
  );
}

class _MultiCaregiverApi extends LifeMateApiClient {
  _MultiCaregiverApi()
    : super(
        baseUri: Uri.parse('https://example.invalid'),
        accessToken: () => 'test-token',
      );

  @override
  Future<Map<String, dynamic>> getWomenCalendarDashboard({
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    final today = DateTime.now();
    final start = DateTime(
      today.year,
      today.month,
      today.day,
    ).subtract(const Duration(days: 2));
    final startText = _isoDate(start);
    return {
      'profile': {
        'enabled': true,
        'lastPeriodStart': startText,
        'cycleLength': 28,
        'periodLength': 5,
        'remindersEnabled': true,
      },
      'episodes': [
        {'id': 'episode-1', 'startedOn': startText, 'endedOn': null},
      ],
      'currentUser': const {
        'user': {'id': 'reyhaneh-user'},
      },
      'currentProfile': const {
        'displayName': 'ریحانه',
        'avatarKey': 'person_purple',
        'profilePhotoUrl': 'https://example.invalid/reyhaneh.jpg',
      },
      'relationships': const [
        {
          'id': 'relationship-hamid-1',
          'status': 'active',
          'patientUserId': 'reyhaneh-user',
          'caregiverUserId': 'hamid-1',
          'caregiverDisplayName': 'حمید ۱',
          'caregiverAvatarKey': 'person_green',
          'caregiverProfilePhotoUrl': 'https://example.invalid/hamid1.jpg',
          'canViewWomenCalendar': true,
        },
        {
          'id': 'relationship-hamid-2',
          'status': 'active',
          'patientUserId': 'reyhaneh-user',
          'caregiverUserId': 'hamid-2',
          'caregiverDisplayName': 'حمید ۲',
          'caregiverAvatarKey': 'person_blue',
          'caregiverProfilePhotoUrl': null,
          'canViewWomenCalendar': true,
        },
        {
          'id': 'relationship-no-calendar',
          'status': 'active',
          'patientUserId': 'reyhaneh-user',
          'caregiverUserId': 'caregiver-no-calendar',
          'caregiverDisplayName': 'بدون دسترسی',
          'caregiverAvatarKey': 'person_orange',
          'caregiverProfilePhotoUrl': null,
          'canViewWomenCalendar': false,
        },
      ],
      'dailyLogs': const [],
      'treatmentPlans': const [],
    };
  }
}

class _NoopWomenCompanionApi extends WomenCompanionApi {
  _NoopWomenCompanionApi()
    : super(
        baseUri: Uri.parse('https://example.invalid'),
        accessToken: () => 'test-token',
      );
}

String _isoDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
