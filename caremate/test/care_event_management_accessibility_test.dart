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
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(1.4),
                ),
                child: const CareEventManagementScreen(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (var index = 0; index < 3; index += 1) {
        final selector =
            find.byKey(ValueKey<String>('caremate-care-type-$index'));
        expect(selector, findsOneWidget);
        expect(tester.getSize(selector).height, greaterThanOrEqualTo(58));
      }

      expect(find.text('فرم ویزیت پزشکی'), findsOneWidget);
      expect(find.text('آدرس کامل'), findsOneWidget);
      expect(find.text('ویزیت‌های ثبت‌شده'), findsOneWidget);
      expect(find.text('ویزیت متخصص قلب'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('caremate-care-type-1')),
      );
      await tester.pumpAndSettle();

      expect(find.text('فرم داروی جدید'), findsOneWidget);
      expect(find.text('برنامه واقعی هفت روز آینده'), findsOneWidget);
      expect(find.text('متفورمین'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('caremate-care-type-2')),
      );
      await tester.pumpAndSettle();

      expect(find.text('فرم تزریقات'), findsOneWidget);
      expect(find.text('تزریق‌های ثبت‌شده'), findsOneWidget);
      expect(find.text('ویتامین B12'), findsOneWidget);
      expect(find.text('ثبت نیازمند مجوز صریح بیمار'), findsOneWidget);
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
