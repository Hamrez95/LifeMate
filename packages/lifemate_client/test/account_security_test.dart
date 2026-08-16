import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

Future<void> _pump(
  WidgetTester tester,
  LifeMateAccountSecurityController controller, {
  bool googleEnabled = false,
  bool phoneEnabled = false,
}) async {
  LifeMateRuntimeLocale.setLanguageCode('en');
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      home: LifeMateAccountSecurityScreen(
        controller: controller,
        accent: Colors.blue,
        background: const Color(0xFFF7F8FA),
        ink: const Color(0xFF172033),
        googleLinkingEnabled: googleEnabled,
        phoneLinkingEnabled: phoneEnabled,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _scrollToKey(WidgetTester tester, String key) async {
  await tester.scrollUntilVisible(
    find.byKey(ValueKey(key)),
    260,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Future<void> _scrollToNotice(WidgetTester tester) =>
    _scrollToKey(tester, 'account-security-notice');

String? _textAtKey(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data;

void main() {
  tearDown(() => LifeMateRuntimeLocale.setLanguageCode('fa'));

  testWidgets('email change stays pending and does not replace current email',
      (tester) async {
    final requests = <String>[];
    final controller = LifeMateAccountSecurityController(
      currentEmail: 'current@example.test',
      requestEmailChange: (email) async => requests.add(email),
      requestPasswordRecovery: (_) async {},
      linkGoogleIdentity: () async {},
    );
    await _pump(tester, controller);

    await tester.enterText(
      find.byKey(const ValueKey('account-security-new-email')),
      'next@example.test',
    );
    await tester.tap(
      find.byKey(const ValueKey('account-security-change-email')),
    );
    await tester.pumpAndSettle();

    expect(requests, ['next@example.test']);
    expect(find.text('current@example.test'), findsOneWidget);
    expect(find.textContaining('Pending confirmation: next@example.test'),
        findsOneWidget);

    await _scrollToNotice(tester);
    expect(find.textContaining('remains authoritative'), findsOneWidget);
  });

  testWidgets('disabled phone linking never invokes provider request',
      (tester) async {
    var requests = 0;
    var verifications = 0;
    final controller = LifeMateAccountSecurityController(
      currentEmail: 'current@example.test',
      currentPhone: '+989121234567',
      requestEmailChange: (_) async {},
      requestPasswordRecovery: (_) async {},
      linkGoogleIdentity: () async {},
      requestPhoneChange: (_) async => requests += 1,
      verifyPhoneChange: (_, __) async => verifications += 1,
    );
    await _pump(tester, controller, phoneEnabled: false);

    await _scrollToKey(tester, 'account-security-change-phone');
    final phoneButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('account-security-change-phone')),
    );
    expect(phoneButton.onPressed, isNull);
    expect(
      find.text('Mobile-number changes are not enabled for this release yet.'),
      findsOneWidget,
    );
    expect(requests, 0);
    expect(verifications, 0);
  });

  testWidgets('phone change remains pending until phone-change verification',
      (tester) async {
    final requests = <String>[];
    final verifications = <String>[];
    final controller = LifeMateAccountSecurityController(
      currentEmail: 'current@example.test',
      currentPhone: '+989121234567',
      requestEmailChange: (_) async {},
      requestPasswordRecovery: (_) async {},
      linkGoogleIdentity: () async {},
      requestPhoneChange: (phone) async => requests.add(phone),
      verifyPhoneChange: (phone, token) async =>
          verifications.add('$phone:$token'),
    );
    await _pump(tester, controller, phoneEnabled: true);

    await _scrollToKey(tester, 'account-security-new-phone');
    await tester.enterText(
      find.byKey(const ValueKey('account-security-new-phone')),
      '۰۹۳۵۱۲۳۴۹۹۹',
    );
    await tester.tap(
      find.byKey(const ValueKey('account-security-change-phone')),
    );
    await tester.pumpAndSettle();

    expect(requests, ['+989351234999']);
    expect(find.byKey(const ValueKey('account-security-pending-phone')),
        findsOneWidget);
    expect(_textAtKey(tester, 'account-security-current-phone'), contains('4567'));
    expect(find.textContaining('Pending verification: +98 ••• •• 4999'),
        findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('account-security-phone-otp')),
      '۱۲۳۴۵۶',
    );
    await tester.tap(
      find.byKey(const ValueKey('account-security-verify-phone')),
    );
    await tester.pumpAndSettle();

    expect(verifications, ['+989351234999:123456']);
    expect(find.byKey(const ValueKey('account-security-pending-phone')),
        findsNothing);
    expect(_textAtKey(tester, 'account-security-current-phone'), contains('4999'));
    expect(_textAtKey(tester, 'account-security-current-phone'), isNot(contains('4567')));

    await _scrollToNotice(tester);
    expect(find.textContaining('No new LifeMate health identity or Person'),
        findsOneWidget);
  });

  testWidgets('same verified phone is rejected before provider request',
      (tester) async {
    var requests = 0;
    final controller = LifeMateAccountSecurityController(
      currentEmail: 'current@example.test',
      currentPhone: '+989121234567',
      requestEmailChange: (_) async {},
      requestPasswordRecovery: (_) async {},
      linkGoogleIdentity: () async {},
      requestPhoneChange: (_) async => requests += 1,
      verifyPhoneChange: (_, __) async {},
    );
    await _pump(tester, controller, phoneEnabled: true);

    await _scrollToKey(tester, 'account-security-new-phone');
    await tester.enterText(
      find.byKey(const ValueKey('account-security-new-phone')),
      '09121234567',
    );
    await tester.tap(
      find.byKey(const ValueKey('account-security-change-phone')),
    );
    await tester.pumpAndSettle();

    expect(requests, 0);
    expect(find.textContaining('already your current verified mobile number'),
        findsOneWidget);
  });

  testWidgets('phone provider failures never render raw phone or OTP details',
      (tester) async {
    final controller = LifeMateAccountSecurityController(
      currentEmail: 'current@example.test',
      requestEmailChange: (_) async {},
      requestPasswordRecovery: (_) async {},
      linkGoogleIdentity: () async {},
      requestPhoneChange: (_) async {
        throw Exception('raw provider +989351234999 otp=123456 SECRET');
      },
      verifyPhoneChange: (_, __) async {},
    );
    await _pump(tester, controller, phoneEnabled: true);

    await _scrollToKey(tester, 'account-security-new-phone');
    await tester.enterText(
      find.byKey(const ValueKey('account-security-new-phone')),
      '09351234999',
    );
    await tester.tap(
      find.byKey(const ValueKey('account-security-change-phone')),
    );
    await tester.pumpAndSettle();

    await _scrollToNotice(tester);
    expect(find.textContaining('Phone change could not be started'),
        findsOneWidget);
    expect(find.textContaining('+989351234999'), findsNothing);
    expect(find.text('123456'), findsNothing);
    expect(find.textContaining('raw provider'), findsNothing);
    expect(find.textContaining('SECRET'), findsNothing);
  });

  testWidgets('disabled Google linking never invokes provider request',
      (tester) async {
    var linkCalls = 0;
    final controller = LifeMateAccountSecurityController(
      currentEmail: 'current@example.test',
      requestEmailChange: (_) async {},
      requestPasswordRecovery: (_) async {},
      linkGoogleIdentity: () async => linkCalls += 1,
    );
    await _pump(tester, controller, googleEnabled: false);

    await _scrollToKey(tester, 'account-security-link-google');
    final linkButton = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('account-security-link-google')),
    );
    expect(linkButton.onPressed, isNull);
    expect(
      find.text('Google linking is not enabled for this release configuration yet.'),
      findsOneWidget,
    );
    expect(linkCalls, 0);
  });

  testWidgets('enabled linking operates only through current-user link callback',
      (tester) async {
    var linkCalls = 0;
    final controller = LifeMateAccountSecurityController(
      currentEmail: 'current@example.test',
      requestEmailChange: (_) async {},
      requestPasswordRecovery: (_) async {},
      linkGoogleIdentity: () async => linkCalls += 1,
    );
    await _pump(tester, controller, googleEnabled: true);

    await _scrollToKey(tester, 'account-security-link-google');
    final linkButton = find.byKey(const ValueKey('account-security-link-google'));
    await tester.tap(linkButton);
    await tester.pumpAndSettle();

    expect(linkCalls, 1);
    expect(find.textContaining('currently signed-in account'), findsOneWidget);
  });

  testWidgets('recovery uses current email and returns generic bounded feedback',
      (tester) async {
    final recovery = <String>[];
    final controller = LifeMateAccountSecurityController(
      currentEmail: 'current@example.test',
      requestEmailChange: (_) async {},
      requestPasswordRecovery: (email) async => recovery.add(email),
      linkGoogleIdentity: () async {},
    );
    await _pump(tester, controller);

    await _scrollToKey(tester, 'account-security-recovery');
    await tester.tap(find.byKey(const ValueKey('account-security-recovery')));
    await tester.pumpAndSettle();

    expect(recovery, ['current@example.test']);
    expect(find.textContaining('If recovery delivery is available'),
        findsOneWidget);
  });

  testWidgets('provider failures never render raw provider or identity details',
      (tester) async {
    final controller = LifeMateAccountSecurityController(
      currentEmail: 'current@example.test',
      requestEmailChange: (_) async {
        throw Exception(
          'Supabase raw error victim@example.test token=VERY_PRIVATE_TOKEN',
        );
      },
      requestPasswordRecovery: (_) async {},
      linkGoogleIdentity: () async {},
    );
    await _pump(tester, controller);

    await tester.enterText(
      find.byKey(const ValueKey('account-security-new-email')),
      'next@example.test',
    );
    await tester.tap(
      find.byKey(const ValueKey('account-security-change-email')),
    );
    await tester.pumpAndSettle();

    await _scrollToNotice(tester);
    expect(find.textContaining('Email change could not be started'),
        findsOneWidget);
    expect(find.textContaining('victim@example.test'), findsNothing);
    expect(find.textContaining('VERY_PRIVATE_TOKEN'), findsNothing);
    expect(find.textContaining('Supabase raw error'), findsNothing);
  });
}
