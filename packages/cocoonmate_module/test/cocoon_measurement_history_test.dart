import 'package:cocoonmate_module/cocoonmate_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('history presents canonical data without a clinical claim',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: CocoonTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: CocoonMeasurementHistoryScreen(
            fa: false,
            state: CocoonMeasurementHistoryState.ready,
            onRetry: () {},
            items: const [
              CocoonMeasurementHistoryItem(
                id: 'canonical-measurement-1',
                metricLabel: 'Weight',
                valueLabel: '62.4 kg',
                recordedAtLabel: '24 September 2026, 09:30',
                syncState: CocoonMeasurementHistorySyncState.confirmed,
                note: 'After breakfast',
              ),
              CocoonMeasurementHistoryItem(
                id: 'device-measurement-2',
                metricLabel: 'Blood pressure',
                valueLabel: '118 / 72 mmHg',
                recordedAtLabel: '23 September 2026, 18:00',
                syncState: CocoonMeasurementHistorySyncState.pending,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Measurement history'), findsOneWidget);
    expect(find.text('62.4 kg'), findsOneWidget);
    expect(find.text('Pending sync'), findsOneWidget);
    expect(find.textContaining('no clinical interpretation'), findsOneWidget);
    expect(find.text('In range'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('history has localized loading, empty, and retry states',
      (tester) async {
    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: CocoonTheme.light(),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: CocoonMeasurementHistoryScreen(
            fa: true,
            state: CocoonMeasurementHistoryState.loading,
            items: const [],
            onRetry: () => retries++,
          ),
        ),
      ),
    );
    expect(find.bySemanticsLabel('در حال آماده‌سازی اندازه‌گیری‌ها'),
        findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        theme: CocoonTheme.light(),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: CocoonMeasurementHistoryScreen(
            fa: true,
            state: CocoonMeasurementHistoryState.empty,
            items: const [],
            onRetry: () => retries++,
          ),
        ),
      ),
    );
    expect(find.text('هنوز اندازه‌گیری‌ای ثبت نشده'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        theme: CocoonTheme.light(),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: CocoonMeasurementHistoryScreen(
            fa: true,
            state: CocoonMeasurementHistoryState.error,
            items: const [],
            onRetry: () => retries++,
          ),
        ),
      ),
    );
    expect(find.text('اندازه‌گیری‌ها به‌روز نشد'), findsOneWidget);
    await tester.tap(find.text('تلاش دوباره'));
    expect(retries, 1);
  });

  testWidgets('cached history remains visible when refresh fails',
      (tester) async {
    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: CocoonTheme.light(),
        home: CocoonMeasurementHistoryScreen(
          fa: false,
          state: CocoonMeasurementHistoryState.error,
          onRetry: () => retries++,
          items: const [
            CocoonMeasurementHistoryItem(
              id: 'cached-1',
              metricLabel: 'Weight',
              valueLabel: '62.4 kg',
              recordedAtLabel: '24 September 2026',
              syncState: CocoonMeasurementHistorySyncState.cached,
            ),
          ],
        ),
      ),
    );

    expect(find.text('Weight'), findsOneWidget);
    expect(find.text('On device'), findsOneWidget);
    expect(find.text('Saved measurements are shown; refresh failed.'),
        findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(retries, 1);
  });
}
