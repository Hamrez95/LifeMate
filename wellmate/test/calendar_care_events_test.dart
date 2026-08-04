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
import 'package:wellmate/screens/calendar/schedule_item_card.dart';

void main() {
  testWidgets(
    'calendar combines future medication appointments and injections from live contracts',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<LifeMateApiClient>.value(
              value: _CalendarApiClient(overdueAppointment: false),
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

  testWidgets('overdue appointment is rendered as missed and red', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<LifeMateApiClient>.value(
            value: _CalendarApiClient(overdueAppointment: true),
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

    final appointmentCard = find.byKey(
      const ValueKey<String>('calendar-event-appointment-1'),
    );
    expect(appointmentCard, findsOneWidget);
    expect(
      find.descendant(
        of: appointmentCard,
        matching: find.byIcon(Icons.warning_amber_rounded),
      ),
      findsWidgets,
    );
    final padding = tester.widget<Padding>(appointmentCard);
    final card = padding.child! as ScheduleItemCard;
    expect(card.item.status, 'missed');
    expect(card.isMissed, isTrue);
  });
}

class _CalendarApiClient extends LifeMateApiClient {
  _CalendarApiClient({required this.overdueAppointment})
      : super(
          baseUri: Uri.parse('https://example.invalid'),
          accessToken: () => 'test-token',
        );

  final bool overdueAppointment;

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static String _time(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';

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
  }) async {
    final appointmentAt = DateTime.now().add(
      Duration(minutes: overdueAppointment ? -30 : 60),
    );
    final injectionAt = DateTime.now().add(const Duration(minutes: 120));

    return [
      {
        'id': 'appointment-1',
        'eventType': 'appointment',
        'title': 'ویزیت متخصص قلب',
        'providerName': 'دکتر سارا راد',
        'centerName': 'مرکز درمانی الوند',
        'addressLine': 'تهران، خیابان ولیعصر',
        'scheduledLocalDate': _date(appointmentAt),
        'scheduledLocalTime': _time(appointmentAt),
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
        'scheduledLocalDate': _date(injectionAt),
        'scheduledLocalTime': _time(injectionAt),
        'status': 'scheduled',
        'version': 1,
      },
    ];
  }
}
