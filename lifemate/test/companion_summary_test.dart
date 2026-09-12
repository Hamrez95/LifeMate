import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate/app/lifemate_app.dart';
import 'package:lifemate/circle/camp_companion_selection.dart';
import 'package:lifemate/circle/camp_companion_selection_view.dart';

void main() {
  CampCompanionCandidate candidate({
    String id = 'a',
    String name = 'Alex',
    String relationship = 'Family',
    bool eligible = true,
    String? ineligibleReason,
  }) => CampCompanionCandidate(
    presentationId: id,
    displayName: name,
    relationshipLabel: relationship,
    isEligible: eligible,
    ineligibleReason: ineligibleReason,
  );

  testWidgets('tap summary contains only presentation-safe Circle state', (
    tester,
  ) async {
    final source = SyntheticCampCompanionSelectionSource(
      candidates: [candidate()],
      selectedPresentationIds: const ['a'],
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

    await tester.tap(find.byKey(const ValueKey('camp-summary-a')));
    await tester.pumpAndSettle();

    expect(find.text('Preview summary — not live relationship or consent state'), findsOneWidget);
    expect(find.text('Relationship'), findsOneWidget);
    expect(find.text('Circle access'), findsOneWidget);
    expect(find.text('Connected'), findsOneWidget);
    expect(find.text('Living Camp'), findsOneWidget);
    expect(find.text('Shown in Camp'), findsOneWidget);
    expect(
      find.textContaining(
        'This summary intentionally contains no health measurements',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('patientUserId'), findsNothing);
    expect(find.textContaining('ConsentedAtUtc'), findsNothing);
    expect(find.textContaining('can_manage_health_record'), findsNothing);
  });

  testWidgets('ineligible relationship still opens truthful limited summary', (
    tester,
  ) async {
    final source = SyntheticCampCompanionSelectionSource(
      candidates: [
        candidate(
          id: 'limited',
          name: 'Sam',
          eligible: false,
          ineligibleReason: 'Permission required',
        ),
      ],
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

    expect(find.byKey(const ValueKey('camp-toggle-limited')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('camp-summary-limited')));
    await tester.pumpAndSettle();

    expect(find.text('Permission required'), findsWidgets);
    expect(find.text('Camp presentation unavailable'), findsOneWidget);
  });

  testWidgets('revoked or switched Person produces unavailable summary', (
    tester,
  ) async {
    final source = _MutableCompanionSource(candidates: [candidate()]);

    await tester.pumpWidget(
      LifeMateApp(
        localeOverride: const Locale('en'),
        home: Scaffold(
          body: CampCompanionSelectionView(source: source, isPersian: false),
        ),
      ),
    );
    await tester.pumpAndSettle();

    source.candidates = const <CampCompanionCandidate>[];
    await tester.tap(find.byKey(const ValueKey('camp-summary-a')));
    await tester.pumpAndSettle();

    expect(find.text('Companion summary unavailable'), findsOneWidget);
    expect(
      find.textContaining(
        'The relationship, consent, or active Person may have changed.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('refresh failure does not fall back to cached details', (
    tester,
  ) async {
    final source = _MutableCompanionSource(candidates: [candidate()]);

    await tester.pumpWidget(
      LifeMateApp(
        localeOverride: const Locale('en'),
        home: Scaffold(
          body: CampCompanionSelectionView(source: source, isPersian: false),
        ),
      ),
    );
    await tester.pumpAndSettle();

    source.failLoads = true;
    await tester.tap(find.byKey(const ValueKey('camp-summary-a')));
    await tester.pumpAndSettle();

    expect(find.text('Companion summary unavailable'), findsOneWidget);
    expect(
      find.textContaining('No cached details are shown.'),
      findsOneWidget,
    );
  });

  testWidgets('Persian summary remains localized and RTL', (tester) async {
    final source = SyntheticCampCompanionSelectionSource(
      candidates: [
        candidate(
          relationship: 'خانواده',
          eligible: false,
          ineligibleReason: 'نیاز به اجازه',
        ),
      ],
    );

    await tester.pumpWidget(
      LifeMateApp(
        localeOverride: const Locale('fa'),
        home: Scaffold(
          body: CampCompanionSelectionView(source: source, isPersian: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('camp-summary-a')));
    await tester.pumpAndSettle();

    expect(find.text('رابطه'), findsOneWidget);
    expect(find.text('دسترسی Circle'), findsOneWidget);
    expect(find.text('نیاز به اجازه'), findsWidgets);
    expect(find.text('نمایش در کمپ در دسترس نیست'), findsOneWidget);
    final directionality = tester.widget<Directionality>(
      find.byType(Directionality).first,
    );
    expect(directionality.textDirection, TextDirection.rtl);
  });
}

class _MutableCompanionSource implements CampCompanionSelectionSource {
  _MutableCompanionSource({required this.candidates});

  List<CampCompanionCandidate> candidates;
  Set<String> selected = <String>{};
  bool failLoads = false;

  @override
  CampCompanionSourceMode get mode => CampCompanionSourceMode.live;

  @override
  Future<CampCompanionSelectionSnapshot> load() async {
    if (failLoads) throw StateError('source unavailable');
    final eligible = candidates
        .where((candidate) => candidate.isEligible)
        .map((candidate) => candidate.presentationId)
        .toSet();
    selected = selected.intersection(eligible);
    return CampCompanionSelectionSnapshot(
      candidates: List<CampCompanionCandidate>.unmodifiable(candidates),
      selectedPresentationIds: Set<String>.unmodifiable(selected),
      capacity: 2,
    );
  }

  @override
  Future<void> setSelectedPresentationIds(Set<String> presentationIds) async {
    selected = Set<String>.from(presentationIds);
  }
}
