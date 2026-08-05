import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wellmate/core/state/wellmate_refresh.dart';

void main() {
  testWidgets('page return invalidates preserved WellMate screens', (
    tester,
  ) async {
    final observer = WellMateNavigationRefreshObserver();
    final navigatorKey = GlobalKey<NavigatorState>();
    final initialRevision = WellMateRefreshSignal.revision.value;

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [observer],
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(body: Text('details')),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('details'), findsOneWidget);

    navigatorKey.currentState!.pop<void>();
    await tester.pumpAndSettle();

    expect(WellMateRefreshSignal.revision.value, initialRevision + 1);
  });

  testWidgets('closing a dialog does not trigger a full data refresh', (
    tester,
  ) async {
    final observer = WellMateNavigationRefreshObserver();
    final initialRevision = WellMateRefreshSignal.revision.value;

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('dialog'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('close'),
                    ),
                  ],
                ),
              ),
              child: const Text('show'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('show'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('close'));
    await tester.pumpAndSettle();

    expect(WellMateRefreshSignal.revision.value, initialRevision);
  });
}
