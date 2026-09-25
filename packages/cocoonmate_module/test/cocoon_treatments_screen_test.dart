import 'package:cocoonmate_module/cocoonmate_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget app(Widget child, {TextDirection direction = TextDirection.ltr}) =>
      MaterialApp(
        theme: CocoonTheme.light(),
        home: Directionality(textDirection: direction, child: child),
      );

  testWidgets('shows only host-injected canonical treatment text',
      (tester) async {
    String? opened;
    await tester.pumpWidget(
      app(
        CocoonTreatmentsScreen(
          fa: false,
          state: CocoonTreatmentsLoadState.ready,
          items: const [
            CocoonActiveTreatmentViewData(
              id: 'canonical-treatment-1',
              title: 'Care-plan item',
              details: 'Display detail supplied by the care plan',
              nextDoseLabel: 'Next scheduled item: 09:30',
              statusLabel: 'Current status supplied by source',
            ),
          ],
          onRetry: () {},
          onOpenTreatment: (id) => opened = id,
        ),
      ),
    );

    expect(find.text('Your care plan'), findsOneWidget);
    expect(find.text('Care-plan item'), findsOneWidget);
    expect(find.text('Next scheduled item: 09:30'), findsOneWidget);
    await tester.tap(find.text('Care-plan item'));
    expect(opened, 'canonical-treatment-1');
    expect(tester.takeException(), isNull);
  });

  testWidgets('loading and empty states do not invent treatment options', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        CocoonTreatmentsScreen(
          fa: false,
          state: CocoonTreatmentsLoadState.loading,
          items: const [],
          onRetry: () {},
          onOpenTreatment: (_) {},
        ),
      ),
    );
    expect(find.bySemanticsLabel('Loading treatments'), findsOneWidget);

    await tester.pumpWidget(
      app(
        CocoonTreatmentsScreen(
          fa: false,
          state: CocoonTreatmentsLoadState.empty,
          items: const [],
          onRetry: () {},
          onOpenTreatment: (_) {},
        ),
      ),
    );
    expect(find.text('No active treatments to show'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('error state is retryable and Persian pending state is explicit',
      (
    tester,
  ) async {
    var retries = 0;
    await tester.pumpWidget(
      app(
        CocoonTreatmentsScreen(
          fa: true,
          state: CocoonTreatmentsLoadState.error,
          items: const [],
          onRetry: () => retries++,
          onOpenTreatment: (_) {},
        ),
        direction: TextDirection.rtl,
      ),
    );
    expect(find.text('درمان‌ها به‌روزرسانی نشدند'), findsOneWidget);
    await tester.tap(find.text('تلاش دوباره'));
    expect(retries, 1);

    await tester.pumpWidget(
      app(
        CocoonTreatmentsScreen(
          fa: true,
          state: CocoonTreatmentsLoadState.error,
          items: const [
            CocoonActiveTreatmentViewData(
              id: 'canonical-treatment-2',
              title: 'مورد برنامه مراقبتی',
              details: 'جزئیات از منبع',
              isPendingSync: true,
            ),
          ],
          onRetry: () => retries++,
          onOpenTreatment: (_) {},
        ),
        direction: TextDirection.rtl,
      ),
    );
    expect(find.text('آخرین فهرست در دسترس درمان‌ها نمایش داده می‌شود.'),
        findsOneWidget);
    expect(find.text('در انتظار همگام‌سازی'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
