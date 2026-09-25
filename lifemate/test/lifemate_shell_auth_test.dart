import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate/app/lifemate_shell_auth.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  testWidgets('shell auth leads with the enabled sign-in method', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: LifeMateShellAuth(isPersian: false)),
    );

    if (LifeMateFeatureFlags.phoneOtpEnabled) {
      expect(find.text('Mobile number'), findsOneWidget);
      expect(find.text('Send verification code'), findsOneWidget);
      expect(find.text('Use email instead'), findsOneWidget);
    } else {
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Sign in'), findsOneWidget);
      expect(find.text('Use mobile number'), findsOneWidget);
    }
  });
}
