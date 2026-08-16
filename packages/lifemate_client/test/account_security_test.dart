import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

Future<void> _pump(
  WidgetTester tester,
  LifeMateAccountSecurityController controller, {
  bool googleEnabled = false,
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
      ),
    ),
  );
  await tester.pumpAndSettle();
}

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
    expect(find.textContaining('remains authoritative'), findsOneWidget);
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

    final linkButton = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('account-security-link-google')),
    );
    expect(linkButton.onPressed, isNull);
    expect(find.textContaining('not enabled for this release'), findsOneWidget);
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

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('account-security-link-google')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('account-security-link-google')));
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

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('account-security-recovery')),
      220,
      scrollable: find.byType(Scrollable).first,
    );
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

    expect(find.textContaining('Email change could not be started'),
        findsOneWidget);
    expect(find.textContaining('victim@example.test'), findsNothing);
    expect(find.textContaining('VERY_PRIVATE_TOKEN'), findsNothing);
    expect(find.textContaining('Supabase raw error'), findsNothing);
  });
}
