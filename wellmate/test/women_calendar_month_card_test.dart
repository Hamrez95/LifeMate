import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';
import 'package:wellmate/localization/locale_provider.dart';
import 'package:wellmate/main.dart';
import 'package:wellmate/providers/settings_provider.dart';
import 'package:wellmate/screens/women_calendar/women_calendar_month_card.dart';

void main() {
  testWidgets(
    'renders cycle ring, Jalali calendar and remains usable on small large-text screens',
    (tester) async {
      final estimate = WomenCalendarEstimate.calculate(
        lastPeriodStart: DateTime(2026, 8, 1),
        cycleLength: 28,
        periodLength: 5,
        today: DateTime(2026, 8, 4),
      );

      await tester.pumpWidget(
        _harness(
          WomenCalendarMonthCard(
            initialFocusedDate: DateTime(2026, 8, 4),
            estimate: estimate,
            episodes: [
              {'startedOn': '2026-08-01', 'endedOn': '2026-08-05'},
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('women-calendar-cycle-ring')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('women-calendar-cycle-phase')),
        findsOneWidget,
      );
      final cycleDay = tester.widget<Text>(
        find.byKey(const ValueKey('women-calendar-cycle-day')),
      );
      expect(cycleDay.data, contains('۴'));
      expect(RegExp(r'[0-9]').hasMatch(cycleDay.data!), isFalse);

      final title = tester.widget<Text>(
        find.byKey(const ValueKey('women-calendar-month-title')),
      );
      expect(title.data, contains('۱۴۰۵'));
      expect(RegExp(r'[0-9]').hasMatch(title.data!), isFalse);
      expect(
        find.byKey(const ValueKey('women-calendar-month-grid')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final settings = SettingsProvider()..updateTextScale(1.5);
      await tester.pumpWidget(
        _harness(
          WomenCalendarMonthCard(
            initialFocusedDate: DateTime(2026, 8, 4),
            estimate: null,
            episodes: const [],
          ),
          settings: settings,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('women-calendar-cycle-ring-empty')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('women-calendar-month-grid')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

Widget _harness(Widget child, {SettingsProvider? settings}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => LocaleProvider()),
      ChangeNotifierProvider.value(value: settings ?? SettingsProvider()),
    ],
    child: WellMateApp(
      key: UniqueKey(),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: child,
        ),
      ),
    ),
  );
}
