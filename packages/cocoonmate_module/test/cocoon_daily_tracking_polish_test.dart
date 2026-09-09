import 'package:cocoonmate_module/cocoonmate_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child, {MediaQueryData? mediaQuery}) => MaterialApp(
      theme: CocoonTheme.light(),
      home: MediaQuery(
        data: mediaQuery ?? const MediaQueryData(),
        child: Scaffold(body: child),
      ),
    );

void main() {
  testWidgets('quick check-in honors platform reduce motion', (tester) async {
    await tester.pumpWidget(
      _app(
        CocoonQuickCheckInScreen(
          fa: false,
          syncState: CocoonCheckInSyncState.idle,
          onSubmit: (_) async {},
        ),
        mediaQuery: const MediaQueryData(disableAnimations: true),
      ),
    );

    final animatedChoices = tester.widgetList<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    expect(animatedChoices, isNotEmpty);
    expect(
      animatedChoices.every((widget) => widget.duration == Duration.zero),
      isTrue,
    );
  });

  testWidgets(
    'quick check-in energy choices reflow on a narrow large-text view',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _app(
          CocoonQuickCheckInScreen(
            fa: true,
            syncState: CocoonCheckInSyncState.idle,
            onSubmit: (_) async {},
          ),
          mediaQuery: const MediaQueryData(
            textScaler: TextScaler.linear(1.5),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(ChoiceChip), findsNWidgets(3));
      expect(find.text('معمولی'), findsOneWidget);
    },
  );

  testWidgets('symptom catalog error is distinct and retryable', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      _app(
        CocoonSymptomLogScreen(
          fa: false,
          options: const [],
          catalogState: CocoonSymptomCatalogState.error,
          submitState: CocoonSymptomSubmitState.idle,
          onSubmit: (_) async {},
          onOpenMedicalAttention: null,
          onRetryCatalog: () => retried = true,
        ),
      ),
    );

    expect(
      find.text('The approved symptom catalog could not be loaded.'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(retried, isTrue);
  });

  testWidgets(
    'symptom loading and empty states never enable submission',
    (tester) async {
      for (final state in <CocoonSymptomCatalogState>[
        CocoonSymptomCatalogState.loading,
        CocoonSymptomCatalogState.empty,
      ]) {
        await tester.pumpWidget(
          _app(
            CocoonSymptomLogScreen(
              fa: false,
              options: const [],
              catalogState: state,
              submitState: CocoonSymptomSubmitState.idle,
              onSubmit: (_) async {},
              onOpenMedicalAttention: null,
            ),
          ),
        );

        final saveButton = tester.widget<FilledButton>(
          find.byType(FilledButton),
        );
        expect(saveButton.onPressed, isNull);
        expect(tester.takeException(), isNull);
      }
    },
  );
}
