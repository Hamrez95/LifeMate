import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wellmate/screens/women_calendar/women_daily_log_visuals.dart';

void main() {
  test('daily log serializes canonical language-neutral values', () {
    final draft = WomenDailyLogDraft(
      loggedOn: DateTime(2026, 8, 30),
      version: 2,
      periodFlow: 'medium',
      bloodAppearance: 'dark_red',
      bloodTexture: 'usual',
      painLevel: 2,
      symptoms: const {'cramps', 'bloating'},
      privateNotes: 'private',
    );
    expect(draft.toApiBody()['periodFlow'], 'medium');
    expect(draft.toApiBody()['bloodAppearance'], 'dark_red');
    expect(draft.toApiBody()['symptoms'], containsAll(<String>['cramps', 'bloating']));
  });

  testWidgets('partner badge is presentation-only and optional', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: PartnerAvatarBadge(isPartner: true, child: ColoredBox(color: Colors.grey)))));
    expect(find.byType(PartnerAvatarBadge), findsOneWidget);
    expect(find.byIcon(Icons.favorite), findsNothing);
  });

  testWidgets('no symptom is exclusive with other symptoms', (tester) async {
    WomenDailyLogDraft? result;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(body: TextButton(onPressed: () async { result = await showWomenDailyLogSheet(context, loggedOn: DateTime(2026, 8, 30)); }, child: const Text('open'))))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final sheetList = find.byType(ListView).last;
    await tester.scrollUntilVisible(
      find.text('No symptom'),
      260,
      scrollable: find.descendant(of: sheetList, matching: find.byType(Scrollable)).first,
    );
    await tester.tap(find.text('No symptom'));
    await tester.pump();
    await tester.ensureVisible(find.text('Cramps'));
    await tester.tap(find.text('Cramps'));
    await tester.pump();
    await tester.ensureVisible(find.text('Save daily log'));
    await tester.tap(find.text('Save daily log'));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.symptoms, contains('cramps'));
    expect(result!.symptoms, isNot(contains('no_symptom')));
  });
}
