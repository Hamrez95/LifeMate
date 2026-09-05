import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wellmate/screens/home/home_offline_status_banner.dart';
import 'package:wellmate/screens/home/home_schedule_loader.dart';

void main() {
  tearDown(() {
    homeOfflinePresentationState.value = const HomeOfflinePresentationState();
  });

  testWidgets('cached Home banner is contextual and non-blocking', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const <Locale>[Locale('en'), Locale('fa')],
        home: Scaffold(
          body: Column(
            children: [
              HomeOfflineStatusBanner(
                cachedAtUtc: DateTime.utc(2026, 9, 5, 6, 30),
              ),
              const Expanded(
                child: Text(
                  'Today schedule remains visible',
                  key: ValueKey('cached-home-content'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('home-offline-status-banner')), findsOneWidget);
    expect(find.text('Saved on this device'), findsOneWidget);
    expect(find.textContaining('Server status will refresh'), findsOneWidget);
    expect(find.byKey(const ValueKey('cached-home-content')), findsOneWidget);
  });

  testWidgets('pending treatment is labelled local and not server confirmed', (
    tester,
  ) async {
    homeOfflinePresentationState.value = const HomeOfflinePresentationState(
      cached: true,
      pendingTreatmentCreateCount: 2,
    );

    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('en'),
        home: Scaffold(body: HomeOfflineStatusBanner()),
      ),
    );

    expect(find.text('Treatment saved on this device'), findsOneWidget);
    expect(find.textContaining('2 treatments are not server-confirmed yet'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(TextButton), findsNothing);
  });

  testWidgets('Persian banner explains local data without calling it confirmed', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Localizations.override(
              context: context,
              locale: const Locale('fa'),
              child: const HomeOfflineStatusBanner(),
            ),
          ),
        ),
      ),
    );

    expect(find.text('اطلاعات ذخیره‌شده روی گوشی'), findsOneWidget);
    expect(find.textContaining('اطلاعات محلی'), findsOneWidget);
    expect(find.textContaining('وضعیت سرور'), findsOneWidget);
  });
}
