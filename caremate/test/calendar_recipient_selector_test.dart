import 'package:caremate/core/localization/locale_provider.dart';
import 'package:caremate/main.dart';
import 'package:caremate/models/user_model.dart';
import 'package:caremate/screens/calendar/calendar_screen.dart';
import 'package:caremate/screens/calendar/user_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets(
    'calendar shows every active recipient and switches patient on selection',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 820);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final api = _RecipientCalendarApiClient();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => LocaleProvider()),
            Provider<LifeMateApiClient>.value(value: api),
          ],
          child: const CareMateApp(home: CalendarScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('care-calendar-recipient-scroll')),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey<String>('care-calendar-recipient-patient-1'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey<String>('care-calendar-recipient-patient-2'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey<String>('care-calendar-recipient-patient-3'),
        ),
        findsOneWidget,
      );
      for (final patientId in const ['patient-1', 'patient-2', 'patient-3']) {
        expect(
          find.byKey(ValueKey<String>('care-calendar-avatar-$patientId')),
          findsOneWidget,
        );
      }
      expect(api.requestedPatientIds.last, 'patient-1');

      await tester.tap(
        find.byKey(
          const ValueKey<String>('care-calendar-recipient-patient-2'),
        ),
      );
      await tester.pumpAndSettle();

      expect(api.requestedPatientIds.last, 'patient-2');
      expect(find.text('داروی مادر'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('recipient selector passes signed photo URL to shared avatar', (
    WidgetTester tester,
  ) async {
    const signedPhoto = 'https://example.invalid/signed/profile-photo';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: UserSelector(
            users: [
              UserModel(
                id: 'patient-photo',
                name: 'ریحانه',
                role: 'فرد تحت مراقبت',
                profilePhotoUrl: signedPhoto,
                avatarKey: 'person_green',
              ),
            ],
            selectedUserId: 'patient-photo',
            font: TextStyle(),
            onUserSelected: _noopSelection,
          ),
        ),
      ),
    );

    final avatar = tester.widget<LifeMateProfileAvatar>(
      find.byKey(
        const ValueKey<String>('care-calendar-avatar-patient-photo'),
      ),
    );
    expect(avatar.photoUrl, signedPhoto);
    expect(avatar.avatarKey, 'person_green');
  });
}

void _noopSelection(String _) {}

class _RecipientCalendarApiClient extends LifeMateApiClient {
  _RecipientCalendarApiClient()
    : super(
        baseUri: Uri.parse('https://example.invalid'),
        accessToken: () => 'test-token',
      );

  final List<String> requestedPatientIds = <String>[];

  String get _today {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  @override
  Future<Map<String, dynamic>> getCurrentUser() async => {
    'user': {'id': 'caregiver-1'},
  };

  @override
  Future<List<Map<String, dynamic>>> getCareRelationships() async => [
    {
      'id': 'relationship-1',
      'status': 'active',
      'patientUserId': 'patient-1',
      'patientDisplayName': 'ریحانه',
      'patientAvatarKey': 'person_green',
      'caregiverUserId': 'caregiver-1',
    },
    {
      'id': 'relationship-2',
      'status': 'active',
      'patientUserId': 'patient-2',
      'patientDisplayName': 'مادر',
      'patientAvatarKey': 'person_purple',
      'caregiverUserId': 'caregiver-1',
    },
    {
      'id': 'relationship-3',
      'status': 'active',
      'patientUserId': 'patient-3',
      'patientDisplayName': 'پدر',
      'patientAvatarKey': 'person_orange',
      'caregiverUserId': 'caregiver-1',
    },
  ];

  @override
  Future<List<Map<String, dynamic>>> getCareRecipientDoseOccurrences({
    required String patientUserId,
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    requestedPatientIds.add(patientUserId);
    final label = switch (patientUserId) {
      'patient-2' => 'داروی مادر',
      'patient-3' => 'داروی پدر',
      _ => 'داروی ریحانه',
    };
    return [
      {
        'id': 'dose-$patientUserId',
        'medicationName': label,
        'doseText': 'یک عدد',
        'scheduledLocalDate': _today,
        'scheduledLocalTime': '09:00',
        'status': 'scheduled',
      },
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> getCareRecipientCareEvents({
    required String patientUserId,
    required DateTime fromDate,
    required DateTime toDate,
  }) async => const [];
}
