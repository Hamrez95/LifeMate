import 'package:caremate/core/localization/locale_provider.dart';
import 'package:caremate/main.dart';
import 'package:caremate/screens/care_event_management_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

void main() {
  tearDown(LifeMateNotice.clearForTesting);

  testWidgets(
    'caregiver with explicit permission can manage medicine visits and injections without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(360, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => LocaleProvider()),
            Provider<LifeMateApiClient>.value(value: _CareMateApiClient()),
          ],
          child: CareMateApp(
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(360, 760),
                textScaler: TextScaler.linear(1.25),
              ),
              child: CareEventManagementScreen(
                managementApi: _CareManagementApi(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('caremate-health-management-granted')),
        findsOneWidget,
      );
      for (var index = 0; index < 3; index += 1) {
        final selector = find.byKey(ValueKey('caremate-care-type-$index'));
        expect(selector, findsOneWidget);
        expect(tester.getSize(selector).height, greaterThanOrEqualTo(58));
      }

      final scrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.text('ویزیت متخصص قلب'),
        180,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();
      expect(find.text('ویزیت متخصص قلب'), findsOneWidget);
      expect(find.text('افزودن ویزیت'), findsOneWidget);
      expect(find.byTooltip('ویرایش'), findsWidgets);
      expect(find.byTooltip('حذف'), findsWidgets);
      expect(tester.takeException(), isNull);

      await _returnManagementToTop(tester, scrollable);
      final medicationSelector = find.byKey(
        const ValueKey('caremate-care-type-1'),
      );
      expect(medicationSelector, findsOneWidget);
      await tester.tap(medicationSelector);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('متفورمین'),
        180,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();
      expect(find.text('متفورمین'), findsOneWidget);
      expect(find.text('افزودن دارو'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await _returnManagementToTop(tester, scrollable);
      final injectionSelector = find.byKey(
        const ValueKey('caremate-care-type-2'),
      );
      expect(injectionSelector, findsOneWidget);
      await tester.tap(injectionSelector);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('ویتامین B12'),
        180,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();
      expect(find.text('ویتامین B12'), findsOneWidget);
      expect(find.text('افزودن تزریق'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('caregiver without explicit permission sees locked management state', (
    tester,
  ) async {
    // This test validates the authorization state itself. A taller viewport
    // keeps the lazy ListView from obscuring the locked card; small-screen
    // scrolling/overflow is covered by the granted-state test above.
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => LocaleProvider()),
          Provider<LifeMateApiClient>.value(value: _CareMateApiClient()),
        ],
        child: CareMateApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(390, 1200)),
            child: CareEventManagementScreen(
              managementApi: _CareManagementApi(canManage: false),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('caremate-health-management-locked')),
      findsOneWidget,
    );
    expect(find.textContaining('مشاهده و ویرایش پرونده سلامت'), findsOneWidget);
    expect(find.text('افزودن دارو'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _returnManagementToTop(
  WidgetTester tester,
  Finder scrollable,
) async {
  // The management body is lazy, so scrolling deeply can dispose the type
  // selector widgets. Move the same scrollable back to its leading edge
  // before trying to switch the management mode again.
  await tester.fling(scrollable, const Offset(0, 1200), 3000);
  await tester.pumpAndSettle();
}

class _CareMateApiClient extends LifeMateApiClient {
  _CareMateApiClient()
    : super(
        baseUri: Uri.parse('https://example.invalid'),
        accessToken: () => 'test-token',
      );

  @override
  Future<Map<String, dynamic>> getCurrentUser() async => {
    'user': {'id': 'caregiver-1'},
    'profile': {'displayName': 'مراقب تست', 'timeZone': 'Asia/Tehran'},
  };

  @override
  Future<Map<String, dynamic>> getCurrentProfile() async => const {
    'displayName': 'مراقب تست',
    'avatarKey': 'caregiver_teal',
    'profilePhotoUrl': null,
  };

  @override
  Future<List<Map<String, dynamic>>> getCareRelationships() async => [
    {
      'id': 'relationship-1',
      'status': 'active',
      'patientUserId': 'patient-1',
      'patientDisplayName': 'مامان جون',
      'caregiverUserId': 'caregiver-1',
    },
  ];
}

class _CareManagementApi extends LifeMateCareManagementApi {
  _CareManagementApi({this.canManage = true})
    : super(
        baseUri: Uri.parse('https://example.invalid'),
        accessToken: () => 'test-token',
      );

  final bool canManage;

  @override
  Future<Map<String, dynamic>> getRelationshipPermission({
    required String relationshipId,
  }) async => {'canManageHealthRecord': canManage};

  @override
  Future<List<Map<String, dynamic>>> getCareEvents({
    required String patientUserId,
  }) async => [
    {
      'id': 'appointment-1',
      'seriesId': 'appointment-1',
      'eventType': 'appointment',
      'title': 'ویزیت متخصص قلب',
      'centerName': 'مرکز درمانی الوند',
      'scheduledLocalDate': '2026-08-12',
      'scheduledLocalTime': '16:30',
      'status': 'scheduled',
      'version': 2,
    },
    {
      'id': 'injection-1',
      'seriesId': 'injection-1',
      'eventType': 'injection',
      'title': 'ویتامین B12',
      'medicationName': 'ویتامین B12',
      'scheduledLocalDate': '2026-08-13',
      'scheduledLocalTime': '10:00',
      'status': 'scheduled',
      'version': 1,
    },
  ];

  @override
  Future<List<Map<String, dynamic>>> getTreatmentPlans({
    required String patientUserId,
  }) async => [
    {
      'id': 'plan-1',
      'patientUserId': patientUserId,
      'medication': {
        'id': 'med-1',
        'name': 'متفورمین',
        'version': 2,
      },
      'doseText': '۱ عدد',
      'startDate': '2026-08-01',
      'endDate': null,
      'timeZone': 'Asia/Tehran',
      'schedules': [
        {'dayOfWeek': 'sunday', 'localTime': '20:00'},
      ],
      'patientReminderMinutesBefore': 30,
      'caregiverReminderMinutesBefore': 60,
      'status': 'active',
      'version': 3,
    },
  ];
}
