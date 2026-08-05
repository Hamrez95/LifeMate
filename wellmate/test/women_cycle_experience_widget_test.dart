import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:wellmate/screens/women_calendar/women_calendar_experience_widgets.dart';

void main() {
  testWidgets('cycle hero remains usable at 320 logical pixels', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final estimate = WomenCalendarEstimate.calculate(
      lastPeriodStart: DateTime.now().subtract(const Duration(days: 13)),
      cycleLength: 28,
      periodLength: 5,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(8),
              child: WomenCycleHeroCard(
                estimate: estimate,
                onOpenCalendar: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('women-emotional-cycle-hero')),
      findsOneWidget,
    );
    expect(find.text('تقویم چرخه'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('daily check-in fields stay scrollable on a narrow phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(8),
              child: WomenDailyCheckInCard(
                mood: 'neutral',
                energy: 3,
                symptoms: const <String>{},
                supportNeed: 'none',
                noteController: controller,
                shareSummary: false,
                saving: false,
                onMoodChanged: (_) {},
                onEnergyChanged: (_) {},
                onSymptomChanged: (_, __) {},
                onSupportNeedChanged: (_) {},
                onShareChanged: (_) {},
                onSave: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('women-daily-check-in-card')),
      findsOneWidget,
    );
    expect(find.text('ثبت حال امروز'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
