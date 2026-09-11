import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate/living_camp/camp_environment.dart';
import 'package:lifemate/living_camp/camp_home.dart';

void main() {
  const resolver = CampDaylightResolver();

  test('fallback uses local 06:00 to 20:00 window', () {
    const preferences = CampEnvironmentPreferences(
      timezoneOffset: Duration.zero,
    );

    expect(
      resolver.resolvePhase(
        nowUtc: DateTime.utc(2026, 1, 1, 5, 59),
        preferences: preferences,
      ),
      CampDayPhase.night,
    );
    expect(
      resolver.resolvePhase(
        nowUtc: DateTime.utc(2026, 1, 1, 6),
        preferences: preferences,
      ),
      CampDayPhase.day,
    );
    expect(
      resolver.resolvePhase(
        nowUtc: DateTime.utc(2026, 1, 1, 19, 59),
        preferences: preferences,
      ),
      CampDayPhase.day,
    );
    expect(
      resolver.resolvePhase(
        nowUtc: DateTime.utc(2026, 1, 1, 20),
        preferences: preferences,
      ),
      CampDayPhase.night,
    );
  });

  test('fallback respects explicit saved-city timezone offset', () {
    final nowUtc = DateTime.utc(2026, 1, 1, 3);

    expect(
      resolver.resolvePhase(
        nowUtc: nowUtc,
        preferences: const CampEnvironmentPreferences(
          timezoneOffset: Duration.zero,
        ),
      ),
      CampDayPhase.night,
    );
    expect(
      resolver.resolvePhase(
        nowUtc: nowUtc,
        preferences: const CampEnvironmentPreferences(
          timezoneOffset: Duration(hours: 3),
        ),
      ),
      CampDayPhase.day,
    );
  });

  test('coarse location produces astronomical daylight without permission', () {
    const preferences = CampEnvironmentPreferences(
      coarseLocation: CampCoarseLocation(latitude: 35.6892, longitude: 51.3890),
      timezoneOffset: Duration(hours: 3, minutes: 30),
    );
    final window = resolver.resolveWindow(
      nowUtc: DateTime.utc(2026, 6, 21, 8),
      preferences: preferences,
    );

    expect(window.usesFallback, isFalse);
    expect(window.sunriseMinute, inInclusiveRange(180, 480));
    expect(window.sunsetMinute, inInclusiveRange(900, 1320));
    expect(window.sunriseMinute, lessThan(window.sunsetMinute));
  });

  test('debug daylight override wins without changing production fallback', () {
    final midnight = DateTime.utc(2026, 1, 1);

    expect(
      resolver.resolvePhase(
        nowUtc: midnight,
        preferences: const CampEnvironmentPreferences(
          timezoneOffset: Duration.zero,
          debugDaylightOverride: CampDaylightOverride.day,
        ),
      ),
      CampDayPhase.day,
    );
    expect(
      resolver.resolvePhase(
        nowUtc: DateTime.utc(2026, 1, 1, 12),
        preferences: const CampEnvironmentPreferences(
          timezoneOffset: Duration.zero,
          debugDaylightOverride: CampDaylightOverride.night,
        ),
      ),
      CampDayPhase.night,
    );
  });

  testWidgets('lifecycle pauses motion and reconstructs daylight on resume', (
    tester,
  ) async {
    var nowUtc = DateTime.utc(2026, 1, 1, 12);

    await tester.pumpWidget(
      MaterialApp(
        home: CampEnvironmentHost(
          preferences: const CampEnvironmentPreferences(
            timezoneOffset: Duration.zero,
          ),
          nowUtc: () => nowUtc,
          builder: (context, state) =>
              Text('${state.phase.name}:${state.motionEnabled}'),
        ),
      ),
    );

    expect(find.text('day:true'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(find.text('day:false'), findsOneWidget);

    nowUtc = DateTime.utc(2026, 1, 1, 22);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('night:true'), findsOneWidget);
  });

  testWidgets('Reduced Motion disables tickers while preserving Camp entry', (
    tester,
  ) async {
    var openedToday = false;

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: CampHome(
              isPersian: false,
              onOpenToday: () => openedToday = true,
              environmentPreferences: const CampEnvironmentPreferences(
                timezoneOffset: Duration.zero,
              ),
              nowUtc: () => DateTime.utc(2026, 1, 1, 12),
            ),
          ),
        ),
      ),
    );

    final tickerMode = tester.widget<TickerMode>(
      find.byKey(const ValueKey<String>('camp-environment-motion')),
    );
    expect(tickerMode.enabled, isFalse);

    final homeHotspot = find.byWidgetPredicate(
      (widget) =>
          widget is Semantics && widget.properties.label == 'LifeMate home',
      description: 'LifeMate home semantic hotspot',
    );
    expect(homeHotspot, findsOneWidget);
    await tester.tap(homeHotspot);
    expect(openedToday, isTrue);
  });
}
