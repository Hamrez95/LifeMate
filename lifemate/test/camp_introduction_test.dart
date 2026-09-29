import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate/living_camp/camp_introduction.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Camp guide explains three steps and finishes cleanly', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  showCampIntroduction(context: context, isPersian: false),
              child: const Text('open guide'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open guide'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome to your LifeMate Camp'), findsOneWidget);
    expect(find.bySemanticsLabel('Step 1 of 3'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('camp-guide-next')));
    await tester.pumpAndSettle();
    expect(find.text('Open a product house'), findsOneWidget);
    expect(find.bySemanticsLabel('Step 2 of 3'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('camp-guide-next')));
    await tester.pumpAndSettle();
    expect(find.text('Move around from the bottom bar'), findsOneWidget);
    expect(find.bySemanticsLabel('Step 3 of 3'), findsOneWidget);
    expect(find.text('Start exploring'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('camp-guide-next')));
    await tester.pumpAndSettle();
    expect(find.byType(CampIntroductionDialog), findsNothing);
  });

  testWidgets('Persian Camp guide uses Persian copy and RTL layout', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fa'),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: CampIntroductionDialog(isPersian: true),
        ),
      ),
    );

    expect(find.text('به دهکدهٔ LifeMate خوش آمدی'), findsOneWidget);
    expect(find.text('رد کردن'), findsOneWidget);
    expect(
      tester
          .widget<Directionality>(find.byType(Directionality).last)
          .textDirection,
      TextDirection.rtl,
    );
  });

  test(
    'completion preference stores only the device-level guide flag',
    () async {
      SharedPreferences.setMockInitialValues({});
      const preferences = CampIntroductionPreferences();

      expect(await preferences.hasCompleted, isFalse);
      await preferences.markCompleted();
      expect(await preferences.hasCompleted, isTrue);

      final store = await SharedPreferences.getInstance();
      expect(store.getKeys(), {'lifemate.camp_intro.v1.completed'});
    },
  );

  testWidgets('profile guide entry points its chevron with locale direction', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: CampIntroductionTile(isPersian: true, onTap: () {}),
          ),
        ),
      ),
    );

    final tile = tester.widget<ListTile>(find.byType(ListTile));
    expect(tile.trailing, isA<Icon>());
    expect((tile.trailing! as Icon).icon, Icons.chevron_left_rounded);
  });
}
