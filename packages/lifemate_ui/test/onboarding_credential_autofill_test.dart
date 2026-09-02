import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_ui/lifemate_ui.dart';

void main() {
  testWidgets('terminal obscure field advertises an existing password', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LifeMateOnboardingTextField(
            theme: LifeMateOnboardingTheme.shared,
            controller: controller,
            label: 'Password',
            obscureText: true,
            textInputAction: TextInputAction.done,
          ),
        ),
      ),
    );

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.autofillHints, orderedEquals([AutofillHints.password]));
  });

  testWidgets('non-terminal obscure field advertises a new password', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LifeMateOnboardingTextField(
            theme: LifeMateOnboardingTheme.shared,
            controller: controller,
            label: 'Create password',
            obscureText: true,
            textInputAction: TextInputAction.next,
          ),
        ),
      ),
    );

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.autofillHints, orderedEquals([AutofillHints.newPassword]));
  });

  testWidgets('explicit caller autofill semantics always win', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LifeMateOnboardingTextField(
            theme: LifeMateOnboardingTheme.shared,
            controller: controller,
            label: 'One-time code',
            obscureText: true,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.oneTimeCode],
          ),
        ),
      ),
    );

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.autofillHints, orderedEquals([AutofillHints.oneTimeCode]));
  });
}
