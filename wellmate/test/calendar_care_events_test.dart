import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';
import 'package:wellmate/localization/locale_provider.dart';
import 'package:wellmate/main.dart';
import 'package:wellmate/providers/medication_provider.dart';
import 'package:wellmate/providers/notification_provider.dart';
import 'package:wellmate/providers/settings_provider.dart';
import 'package:wellmate/screens/calendar/calendar_screen.dart';

void main() {
  testWidgets(
    'calendar combines medication appointments and injections from live contracts',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<LifeMateApiClient>.value(value: _CalendarApiClient()),
            ChangeNotifierProvider(create: (_) => NotificationProvider()),
            ChangeNotifierProvider(create: (_) => LocaleProvider()),
            ChangeNotifierProvider(create: (_) => SettingsProvider()),
            ChangeNotifierProvider(create: (_) => MedicationProvider()),
          ],
          child: const WellMateApp(home: CalendarScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final eventListFinder = find.byWidgetPredicate(
        (widget) =>
            widget is ListView &&
            widget.physics is NeverScrollableScrollPhysics,
        description: 'the non-scrollable daily event list',
      );
      expect(eventListFinder, findsOneWidget);

      final eventList = tester.widget<ListView>(eventListFinder);
      expect(eventList.childrenDelegate.estimatedChildCount, 2);

      // The nested shrink-wrapped builder virtualizes children outside the test
      // viewport. Build the actual delegate children deterministically so this
      // contract test verifies both mappings and their real card rendering,
      // without depending on offstage/lazy-list behavior.
      final delegate =
          eventList.childrenDelegate as SliverChildBuilderDelegate;
      final listContext = tester.element(eventListFinder);
      final renderedChildren = <Widget>[];
      for (var index = 0; index < 2; index += 1) {
        final child = delegate.builder(listContext, index);
        expect(child, isNotNull, reason: 'event $index must be renderable');
        renderedChildren.add(child!);
      }

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('fa'),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(children: renderedChildren),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('ویزیت متخصص قلب'), findsOneWidget);
      expect(find.byIcon(Icons.medical_services_rounded), findsOneWidget);
      expect(find.textContaining('مرکز درمانی الوند'), findsOneWidget);

      expect(find.text('ویتامین B12'), findsOneWidget);
      expect(find.byIcon(Icons.vaccines_rounded), findsOneWidget);
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
  Future<List<Map<String, dynamic>>> getTreatmentPlans() async => const [];

  @override
  Future<List<Map<String, dynamic>>> getDoseOccurrences({
    required DateTime fromDate,
    required DateTime toDate,
  }) async => const [];

  @override
  Future<List<Map<String, dynamic>>> getCareEvents({
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
          'version': 1,
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
          'version': 1,
        },
      ];
}
