import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate/app/lifemate_app.dart';
import 'package:lifemate/circle/camp_companion_selection.dart';
import 'package:lifemate/circle/camp_companion_selection_view.dart';
import 'package:lifemate/navigation/shell_navigation.dart';
import 'package:lifemate/shell/lifemate_shell.dart';

void main() {
  CampCompanionCandidate candidate(
    String id,
    String name, {
    bool eligible = true,
  }) => CampCompanionCandidate(
    presentationId: id,
    displayName: name,
    relationshipLabel: 'Family',
    isEligible: eligible,
    ineligibleReason: eligible ? null : 'Permission required',
  );

  test(
    'synthetic source enforces eligibility and configured capacity',
    () async {
      final source = SyntheticCampCompanionSelectionSource(
        candidates: [
          candidate('a', 'A'),
          candidate('b', 'B'),
          candidate('c', 'C', eligible: false),
        ],
        capacity: 1,
      );

      await source.setSelectedPresentationIds({'a', 'c'});
      final snapshot = await source.load();
      expect(snapshot.selectedPresentationIds, {'a'});

      await expectLater(
        source.setSelectedPresentationIds({'a', 'b'}),
        throwsA(isA<StateError>()),
      );
    },
  );

  testWidgets('selection is explicit, capacity-bound and privacy-safe', (
    tester,
  ) async {
    final source = SyntheticCampCompanionSelectionSource(
      candidates: [candidate('a', 'Alex'), candidate('b', 'Sam')],
      capacity: 1,
    );

    await tester.pumpWidget(
      LifeMateApp(
        localeOverride: const Locale('en'),
        home: Scaffold(
          body: CampCompanionSelectionView(source: source, isPersian: false),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Preview data — not live relationship or consent state'),
      findsOneWidget,
    );
    expect(find.text('0 of 1 selected'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('camp-toggle-a')));
    await tester.pumpAndSettle();
    expect(find.text('1 of 1 selected'), findsOneWidget);
    expect(
      find.text(
        'Camp display limit reached. Remove a selected companion before adding another.',
      ),
      findsOneWidget,
    );

    final samToggle = find.byKey(const ValueKey('camp-toggle-b'));
    await tester.ensureVisible(samToggle);
    await tester.pumpAndSettle();
    await tester.tap(samToggle);
    await tester.pump();

    final snapshot = await source.load();
    expect(snapshot.selectedPresentationIds, {'a'});
  });

  testWidgets('ineligible candidate cannot be selected', (tester) async {
    final source = SyntheticCampCompanionSelectionSource(
      candidates: [candidate('blocked', 'Taylor', eligible: false)],
    );

    await tester.pumpWidget(
      LifeMateApp(
        localeOverride: const Locale('en'),
        home: Scaffold(
          body: CampCompanionSelectionView(source: source, isPersian: false),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Permission required'), findsOneWidget);
    expect(find.byKey(const ValueKey('camp-toggle-blocked')), findsNothing);
    expect((await source.load()).selectedPresentationIds, isEmpty);
  });

  testWidgets('unavailable source is truthful and Persian remains RTL', (
    tester,
  ) async {
    await tester.pumpWidget(
      const LifeMateApp(
        localeOverride: Locale('fa'),
        home: Scaffold(
          body: CampCompanionSelectionView(
            source: UnavailableCampCompanionSelectionSource(),
            isPersian: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('انتخاب همراهان کمپ هنوز متصل نیست.'), findsOneWidget);
    final directionality = tester.widget<Directionality>(
      find.byType(Directionality).first,
    );
    expect(directionality.textDirection, TextDirection.rtl);
  });

  testWidgets('shell Circle destination mounts injected companion source', (
    tester,
  ) async {
    final source = SyntheticCampCompanionSelectionSource(
      candidates: [candidate('a', 'Alex')],
    );

    await tester.pumpWidget(
      LifeMateApp(
        localeOverride: const Locale('en'),
        home: LifeMateShell(
          initialDestination: ShellDestination.circle,
          campCompanionSource: source,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Camp companions'), findsOneWidget);
    expect(find.text('Alex'), findsOneWidget);
    expect(find.text('0 of 2 selected'), findsOneWidget);
  });
}
