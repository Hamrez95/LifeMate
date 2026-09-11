import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate/app/lifemate_app.dart';
import 'package:lifemate/shell/lifemate_shell.dart';
import 'package:lifemate/today/today_contract.dart';

void main() {
  TodayItem item({
    required String id,
    required String title,
    required TodayRankTier rank,
    required String sortKey,
    TodaySeverity severity = TodaySeverity.normal,
    TodayOwnerKind ownerKind = TodayOwnerKind.currentPerson,
    String ownerName = 'You',
  }) {
    return TodayItem(
      itemId: id,
      sourceModuleId: 'wellmate',
      owner: TodayOwnerPresentation(
        kind: ownerKind,
        presentationId: 'owner-$id',
        displayName: ownerName,
      ),
      display: TodayDisplayContent(
        title: title,
        timeLabel: '09:00',
        sourceLabel: 'WellMate',
      ),
      severity: severity,
      rankTier: rank,
      stableSortKey: sortKey,
    );
  }

  testWidgets('Camp home opens top three and View full day shows all', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final source = SyntheticTodaySource(
      TodaySnapshot(
        generatedAt: DateTime.utc(2026, 9, 11, 8),
        items: [
          item(
            id: 'later',
            title: 'Later item',
            rank: TodayRankTier.later,
            sortKey: '4',
          ),
          item(
            id: 'personal',
            title: 'Personal priority',
            rank: TodayRankTier.personalPriority,
            sortKey: '3',
          ),
          item(
            id: 'urgent',
            title: 'Safety item',
            rank: TodayRankTier.safetyOrOverdue,
            sortKey: '1',
            severity: TodaySeverity.urgent,
          ),
          item(
            id: 'soon',
            title: 'Due soon item',
            rank: TodayRankTier.dueSoon,
            sortKey: '2',
            ownerKind: TodayOwnerKind.companion,
            ownerName: 'Rey',
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      LifeMateApp(
        home: LifeMateShell(todaySource: source),
        localeOverride: const Locale('en'),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('camp-zone-hit-lifemate_home')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Preview data — not live health state'), findsOneWidget);
    expect(find.text('Safety item'), findsOneWidget);
    expect(find.text('Due soon item'), findsOneWidget);
    expect(find.text('Personal priority'), findsOneWidget);
    expect(find.text('Later item'), findsNothing);
    expect(find.text('Urgent'), findsOneWidget);
    expect(find.text('Rey'), findsOneWidget);

    await tester.tap(find.text('View full day'));
    await tester.pumpAndSettle();

    expect(find.text('Your full day'), findsOneWidget);
    expect(find.text('Safety item'), findsOneWidget);
    expect(find.text('Due soon item'), findsOneWidget);
    expect(find.text('Personal priority'), findsOneWidget);
    expect(find.text('Later item'), findsOneWidget);
  });

  testWidgets('default source never fabricates live Today data', (
    tester,
  ) async {
    await tester.pumpWidget(
      const LifeMateApp(home: LifeMateShell(), localeOverride: Locale('en')),
    );

    await tester.tap(find.text('Today').last);
    await tester.pumpAndSettle();

    expect(find.text('Today is not connected yet'), findsOneWidget);
    expect(
      find.text('No synthetic task or health state is shown as live data.'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('cached partial data is explicitly disclosed', (tester) async {
    final source = SyntheticTodaySource(
      TodaySnapshot(
        generatedAt: DateTime.utc(2026, 9, 11, 8),
        freshness: TodayFreshness.cached,
        completeness: TodayCompleteness.partial,
        items: [
          item(
            id: 'one',
            title: 'Safe cached item',
            rank: TodayRankTier.dueSoon,
            sortKey: '1',
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      LifeMateApp(
        home: LifeMateShell(todaySource: source),
        localeOverride: const Locale('en'),
      ),
    );

    await tester.tap(find.text('Today').last);
    await tester.pumpAndSettle();

    expect(find.text('Showing the last safe refresh'), findsOneWidget);
    expect(find.text('Some information could not refresh'), findsOneWidget);
    expect(find.text('Safe cached item'), findsOneWidget);
  });
}
