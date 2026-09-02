import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keyboard-aware onboarding lets Scaffold own IME resizing', () {
    final source = File('lib/src/onboarding_components.dart').readAsStringSync();

    expect(source, contains('resizeToAvoidBottomInset: keyboardAware'));
    expect(source, contains('keyboardVisible'));
    expect(source, contains('compact: keyboardVisible'));
    expect(source, isNot(contains('EdgeInsets.only(bottom: bottomInset)')));
  });

  test('shared auth becomes compact while keyboard is visible', () {
    final source = File('lib/src/shared_auth_experience.dart').readAsStringSync();

    expect(source, contains('MediaQuery.viewInsetsOf(context).bottom > 0'));
    expect(source, contains('if (!keyboardVisible)'));
    expect(source, contains('width: 68'));
    expect(source, contains('fontSize: 20'));
    expect(source, contains('minimumSize: const WidgetStatePropertyAll(Size(0, 44))'));
  });

  test('Android OTP uses SMS User Consent without SMS read permission', () {
    final auth = File('lib/src/shared_auth_experience.dart').readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(pubspec, contains('smart_auth: 3.2.0'));
    expect(auth, contains('SmartAuth.instance'));
    expect(auth, contains('getSmsWithUserConsentApi()'));
    expect(auth, contains('removeUserConsentApiListener()'));
    expect(auth, contains("code.replaceAll(RegExp(r'\\D'), '')"));
    expect(auth, contains('digits.length != 6'));
    expect(auth, isNot(contains('READ_SMS')));
    expect(auth, isNot(contains('debugPrint(')));
  });
}
