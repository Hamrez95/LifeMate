import 'package:cocoonmate_module/cocoonmate_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('mood capture is non-diagnostic, accessible, and submits selection', (
    tester,
  ) async {
    CocoonMoodDraft? submitted;
    await tester.pumpWidget(
      MaterialApp(
        theme: CocoonTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: CocoonMoodLogScreen(
            fa: false,
            submitState: CocoonMoodSubmitState.idle,
            onSubmit: (draft) async => submitted = draft,
          ),
        ),
      ),
    );

    expect(
      find.text('A short self-check-in. This does not diagnose or label you.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Good'));
    await tester.pump();
    await tester.ensureVisible(find.text('Save mood'));
    await tester.tap(find.text('Save mood'));
    await tester.pump();

    expect(submitted?.mood, CocoonMood.good);
    expect(find.bySemanticsLabel('Good'), findsOneWidget);
  });
}
