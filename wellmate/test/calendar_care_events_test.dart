import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';
import 'package:wellmate/localization/locale_provider.dart';
import 'package:wellmate/main.dart';
import 'package:wellmate/models/schedule_item_model.dart';
import 'package:wellmate/providers/medication_provider.dart';
import 'package:wellmate/providers/notification_provider.dart';
import 'package:wellmate/providers/settings_provider.dart';
import 'package:wellmate/screens/calendar/calendar_screen.dart';
import 'package:wellmate/screens/calendar/schedule_item_card.dart';

void main() {
  testWidgets(
    'calendar combines appointments and injections from live contracts',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<LifeMateApiClient>.value(
              value: _CalendarApiClient(),
            ),
            ChangeNotifierProvider(create: (_) => NotificationProvider()),
            ChangeNotifierProvider(create: (_) => LocaleProvider()),
            ChangeNotifierProvider(create: (_) => SettingsProvider()),
            ChangeNotifierProvider(create: (_) => MedicationProvider()),
          ],
          child: const WellMateApp(home: CalendarScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('calendar-event-list')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('calendar-event-appointment-1')),
        findsOneWidget,
      );
      final injectionCard =
          find.byKey(const ValueKey<String>('calendar-event-injection-1'));
      expect(injectionCard, findsOneWidget);

      expect(
        find.text('ویزیت متخصص قلب', skipOffstage: false),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.medical_services_rounded), findsOneWidget);
      expect(
        find.textContaining('مرکز درمانی الوند', skipOffstage: false),
        findsOneWidget,
      );

      // Verify both the canonical live payload and the localized production
      // rendering. Persian UI intentionally converts the numeric suffix in B12.
      final injectionPadding = tester.widget<Padding>(injectionCard);
      final injectionWidget = injectionPadding.child! as ScheduleItemCard;
      expect(injectionWidget.item.title, 'ویتامین B12');
      expect(injectionWidget.item.type, 'injection');
      expect(injectionWidget.item.dosage, contains('مرکز تزریقات'));

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('fa'),
          home: Scaffold(body: injectionWidget),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('ویتامین B۱۲'), findsOneWidget);
      expect(find.byIcon(Icons.vaccines_rounded), findsOneWidget);
      expect(find.textContaining('مرکز تزریقات'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('missed appointment card uses warning styling', (
    WidgetTester tester,
  ) async {
    final item = ScheduleItemModel(
      id: 'appointment-missed',
      title: 'ویزیت متخصص قلب',
      time: '18:20',
      dosage: 'دکتر سارا راد • مرکز درمانی الوند',
      type: 'appointment',
      frequency: 'ویزیت',
      status: 'missed',
      version: 1,
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fa'),
        home: Scaffold(
          body: ScheduleItemCard(
            key: const ValueKey<String>('missed-appointment-card'),
            item: item,
            loc: const <String, String>{},
            isPersian: true,
            isMissed: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final card = find.byKey(
      const ValueKey<String>('missed-appointment-card'),
    );
    expect(card, findsOneWidget);
    expect(
      find.descendant(
        of: card,
        matching: find.byIcon(Icons.warning_amber_rounded),
      ),
      findsWidgets,
    );
    final widget = tester.widget<ScheduleItemCard>(card);
    expect(widget.item.status, 'missed');
    expect(widget.isMissed, isTrue);
  });
}

class _CalendarApiClient extends LifeMateApiClient {
  _CalendarApiClient()
      : super(
          baseUri: Uri.parse('https://example.invalid'),
          accessToken: () => 'test-token',
        );

  String get _today {
    final value = DateTime.now();
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
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
          'scheduledLocalTime': '00:01',
          'status': 'completed',
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
          'scheduledLocalTime': '00:02',
          'status': 'completed',
          'version': 1,
        },
      ];
}
