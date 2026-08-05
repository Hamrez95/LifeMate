import 'package:caremate/core/localization/locale_provider.dart';
import 'package:caremate/main.dart';
import 'package:caremate/screens/care_event_management_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets(
    'care workspace separates visits medicine and injections without overflow',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 640);
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
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.4)),
                child: const CareEventManagementScreen(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final scrollable = find.byType(Scrollable).first;

      Future<void> reveal(Finder target, [double delta = 280]) async {
        await tester.scrollUntilVisible(target, delta, scrollable: scrollable);
        await tester.pumpAndSettle();
      }

      final visitSelector = find.byKey(
        const ValueKey<String>('caremate-care-type-0'),
        skipOffstage: false,
      );
      await reveal(visitSelector, 220);

      for (var index = 0; index < 3; index += 1) {
        final selector = find.byKey(
          ValueKey<String>('caremate-care-type-$index'),
          skipOffstage: false,
        );
        expect(selector, findsOneWidget);
        expect(tester.getSize(selector).height, greaterThanOrEqualTo(58));
      }

      final visitForm = find.text('فرم ویزیت پزشکی', skipOffstage: false);
      await reveal(visitForm);
      expect(visitForm, findsOneWidget);

      final visitAddress = find.text('آدرس کامل', skipOffstage: false);
      await reveal(visitAddress);
      expect(visitAddress, findsOneWidget);

      final visitHeading = find.text('ویزیت‌های ثبت‌شده', skipOffstage: false);
      await reveal(visitHeading, 320);
      expect(visitHeading, findsOneWidget);

      final visitCard = find.text('ویزیت متخصص قلب', skipOffstage: false);
      await reveal(visitCard, 220);
      expect(visitCard, findsOneWidget);
      expect(tester.takeException(), isNull);

      final medicineSelector = find.byKey(
        const ValueKey<String>('caremate-care-type-1'),
        skipOffstage: false,
      );
      await reveal(medicineSelector, -400);
      await tester.tap(medicineSelector);
      await tester.pumpAndSettle();

      final medicineForm = find.text('فرم داروی جدید', skipOffstage: false);
      await reveal(medicineForm);
      expect(medicineForm, findsOneWidget);

      final medicineHeading = find.text(
        'برنامه واقعی هفت روز آینده',
        skipOffstage: false,
      );
      await reveal(medicineHeading, 340);
      expect(medicineHeading, findsOneWidget);

      final medicineCard = find.text('متفورمین', skipOffstage: false);
      await reveal(medicineCard, 180);
      expect(medicineCard, findsOneWidget);
      expect(tester.takeException(), isNull);

      final injectionSelector = find.byKey(
        const ValueKey<String>('caremate-care-type-2'),
        skipOffstage: false,
      );
      await reveal(injectionSelector, -400);
      await tester.tap(injectionSelector);
      await tester.pumpAndSettle();

      final injectionForm = find.text('فرم تزریقات', skipOffstage: false);
      await reveal(injectionForm);
      expect(injectionForm, findsOneWidget);

      final lockedAction = find.text(
        'ثبت نیازمند مجوز صریح بیمار',
        skipOffstage: false,
      );
      await reveal(lockedAction, 320);
      expect(lockedAction, findsOneWidget);

      final injectionHeading = find.text(
        'تزریق‌های ثبت‌شده',
        skipOffstage: false,
      );
      await reveal(injectionHeading, 300);
      expect(injectionHeading, findsOneWidget);

      final injectionCard = find.text('ویتامین B۱۲', skipOffstage: false);
      await reveal(injectionCard, 180);
      expect(injectionCard, findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
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
  Future<List<Map<String, dynamic>>> getCareRelationships() async => [
    {
      'id': 'relationship-1',
      'status': 'active',
      'patientUserId': 'patient-1',
      'patientDisplayName': 'مامان جون',
      'caregiverUserId': 'caregiver-1',
    },
  ];

  @override
  Future<List<Map<String, dynamic>>> getCareRecipientDoseOccurrences({
    required String patientUserId,
    required DateTime fromDate,
    required DateTime toDate,
  }) async => [
    {
      'id': 'dose-1',
      'medicationName': 'متفورمین',
      'scheduledLocalTime': '20:00',
      'status': 'scheduled',
    },
  ];

  @override
  Future<List<Map<String, dynamic>>> getCareRecipientCareEvents({
    required String patientUserId,
    required DateTime fromDate,
    required DateTime toDate,
  }) async => [
    {
      'id': 'appointment-1',
      'eventType': 'appointment',
      'title': 'ویزیت متخصص قلب',
      'centerName': 'مرکز درمانی الوند',
      'addressLine': 'تهران، خیابان ولیعصر',
      'scheduledLocalDate': '2026-08-04',
      'scheduledLocalTime': '16:30',
    },
    {
      'id': 'injection-1',
      'eventType': 'injection',
      'title': 'ویتامین B12',
      'centerName': 'درمانگاه خانواده',
      'addressLine': 'تهران، میدان ونک',
      'scheduledLocalDate': '2026-08-05',
      'scheduledLocalTime': '10:00',
    },
  ];
}
