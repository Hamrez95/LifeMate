import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  group('LifeMatePasswordPolicy', () {
    test('accepts a password meeting every closed-beta requirement', () {
      expect(LifeMatePasswordPolicy.accepts('SafeLifeMate1!'), isTrue);
      expect(
        LifeMatePasswordPolicy.firstViolation('SafeLifeMate1!'),
        isNull,
      );
    });

    test('requires at least twelve characters', () {
      expect(
        LifeMatePasswordPolicy.firstViolation('Short1!Aa'),
        LifeMatePasswordViolation.tooShort,
      );
    });

    test('requires lowercase', () {
      expect(
        LifeMatePasswordPolicy.firstViolation('SAFELIFEMATE1!'),
        LifeMatePasswordViolation.missingLowercase,
      );
    });

    test('requires uppercase', () {
      expect(
        LifeMatePasswordPolicy.firstViolation('safelifemate1!'),
        LifeMatePasswordViolation.missingUppercase,
      );
    });

    test('requires a digit', () {
      expect(
        LifeMatePasswordPolicy.firstViolation('SafeLifeMate!!'),
        LifeMatePasswordViolation.missingDigit,
      );
    });

    test('requires a symbol', () {
      expect(
        LifeMatePasswordPolicy.firstViolation('SafeLifeMate12'),
        LifeMatePasswordViolation.missingSymbol,
      );
    });
  });

  group('recovery auth error redaction', () {
    setUp(() => LifeMateRuntimeLocale.setLanguageCode('en'));
    tearDown(() => LifeMateRuntimeLocale.setLanguageCode('fa'));

    test('keeps provider-specific details out of generic user copy', () {
      const providerMessage =
          'Auth provider database detail: user id 123 failed policy xyz';
      final safe = safeRecoveryAuthMessage(
        providerMessage,
        isPersian: false,
      );
      expect(safe, isNot(contains('provider')));
      expect(safe, isNot(contains('user id')));
      expect(safe, isNot(contains('policy xyz')));
      expect(
        classifyRecoveryAuthFailure(providerMessage),
        LifeMateRecoveryAuthFailure.unavailable,
      );
    });

    test('keeps only the actionable rate-limit distinction', () {
      const providerMessage = 'Rate limit exceeded for endpoint /token';
      final safe = safeRecoveryAuthMessage(
        providerMessage,
        isPersian: false,
      );
      expect(
        classifyRecoveryAuthFailure(providerMessage),
        LifeMateRecoveryAuthFailure.rateLimited,
      );
      expect(safe.toLowerCase(), contains('too many requests'));
      expect(safe, isNot(contains('/token')));
    });
  });
}
