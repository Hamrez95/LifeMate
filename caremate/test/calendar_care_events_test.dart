import 'package:caremate/core/localization/locale_provider.dart';
import 'package:caremate/main.dart';
import 'package:caremate/screens/calendar/calendar_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets(
    'calendar combines medicine visits and injections for active patient',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 820);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => LocaleProvider()),
            Provider<LifeMateApiClient>.value(value: _CalendarApiClient()),
          ],
          child: const CareMateApp(home: CalendarScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('متفورمین'), findsOneWidget);
      expect(find.text('ویزیت متخصص قلب'), findsOneWidget);
      expect(find.text('ویتامین B12'), findsOneWidget);
      expect(find.byIcon(Icons.medical_services_rounded), findsWidgets);
      expect(find.byIcon(Icons.vaccines_rounded), findsWidgets);
      expect(find.textContaining('مرکز درمانی الوند'), findsOneWidget);
      expect(find.textContaining('مرکز تزریقات'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

class _CalendarApiClient extends LifeMateApiClient {
  _CalendarApiClient()
      : super(
          baseUri: Uri.parse('https://example.invalid'),
          accessToken: () => 'test-token',
        );

  String get _today {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  @override
  Future<Map<String, dynamic>> getCurrentUser() async => {
        'user': {'id': 'caregiver-1'},
        'profile': {'displayName': 'مراقب تست'},
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
          'doseText': 'یک عدد',
          'scheduledLocalDate': _today,
          'scheduledLocalTime': '08:00',
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
          'providerName': 'دکتر سارا راد',
          'centerName': 'مرکز درمانی الوند',
          'addressLine': 'تهران، خیابان ولیعصر',
          'scheduledLocalDate': _today,
          'scheduledLocalTime': '16:30',
          'status': 'scheduled',
        },
        {
          'id': 'injection-1',
          'eventType': 'injection',
          'title': 'ویتامین B12',
          'doseText': '۱ آمپول',
          'administrationRoute': 'intramuscular',
          'centerName': 'مرکز تزریقات',
          'addressLine': 'تهران، میدان ونک',
          'scheduledLocalDate': _today,
          'scheduledLocalTime': '18:00',
          'status': 'scheduled',
        },
      ];
}
