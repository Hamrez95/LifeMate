import 'package:caremate/screens/calendar/calendar_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Persian CareMate calendar is Jalali with correct RTL arrows', (
    tester,
  ) async {
    DateTime? page;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fa'),
        supportedLocales: const [Locale('fa'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: CalendarView(
            focusedMonth: DateTime(2026, 8, 4),
            selectedDate: DateTime(2026, 8, 4),
            onDaySelected: (_, __) {},
            onPageChanged: (value) => page = value,
            getDayEventTypes: (_) => const {},
            hasOverdueEvents: (_) => false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('مرداد ۱۴۰۵'), findsOneWidget);
    expect(find.text('ژوئیه'), findsNothing);
    expect(
      find.byKey(const ValueKey('caremate-previous-month')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('caremate-previous-month')),
        matching: find.byIcon(Icons.chevron_right_rounded),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('caremate-next-month')),
        matching: find.byIcon(Icons.chevron_left_rounded),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('caremate-next-month')));
    await tester.pump();
    expect(page, isNotNull);
    expect(page!.isAfter(DateTime(2026, 8, 4)), isTrue);
  });
}
