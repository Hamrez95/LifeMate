import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';
import 'package:wellmate/localization/locale_provider.dart';
import 'package:wellmate/main.dart';
import 'package:wellmate/providers/settings_provider.dart';
import 'package:wellmate/screens/women_calendar/women_calendar_month_card.dart';

void main() {
  testWidgets('cycle overview uses the phase character and target card layout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final estimate = WomenCalendarEstimate.calculateFromEpisodes(
      lastPeriodStart: DateTime(2026, 8, 1),
      configuredCycleLength: 28,
      periodLength: 5,
      periodStarts: [
        DateTime(2026, 5, 9),
        DateTime(2026, 6, 6),
        DateTime(2026, 7, 4),
        DateTime(2026, 8, 1),
      ],
      today: DateTime(2026, 8, 4),
    );

    await tester.pumpWidget(
      _harness(
        WomenCalendarMonthCard(
          initialFocusedDate: DateTime(2026, 8, 4),
          estimate: estimate,
          episodes: const [
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
      find.byKey(const ValueKey('women-calendar-current-phase-character')),
      findsOneWidget,
    );
    expect(find.text('مراحل پیش رو'), findsOneWidget);

    final image = tester.widget<Image>(
      find.byKey(const ValueKey('women-calendar-current-phase-character')),
    );
    expect(image.image, isA<AssetImage>());
    expect(
      (image.image as AssetImage).assetName,
      'feature_assets/women_cycle/period.webp',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('unreliable cycle history keeps fertility timing hidden', (
    tester,
  ) async {
    final estimate = WomenCalendarEstimate.calculateFromEpisodes(
      lastPeriodStart: DateTime(2026, 8, 1),
      configuredCycleLength: 28,
      periodLength: 5,
      periodStarts: [DateTime(2026, 8, 1)],
      today: DateTime(2026, 8, 12),
    );
    expect(estimate.fertilityEstimateReliable, isFalse);

    await tester.pumpWidget(
      _harness(
        WomenCalendarMonthCard(
          initialFocusedDate: DateTime(2026, 8, 12),
          estimate: estimate,
          episodes: const [
            {'startedOn': '2026-08-01', 'endedOn': '2026-08-05'},
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('روزهای باروری'), findsNothing);
    expect(find.text('تخمک‌گذاری'), findsNothing);
    expect(find.byIcon(Icons.info_outline_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _harness(Widget child) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => LocaleProvider()),
      ChangeNotifierProvider(create: (_) => SettingsProvider()),
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
