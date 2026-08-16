import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('WellMate and CareMate use isolated OAuth callback schemes', () {
    expect(
      LifeMateAuth.callbackUrlForApp('WellMate'),
      'com.lifemate.wellmate://login-callback/',
    );
    expect(
      LifeMateAuth.callbackUrlForApp('CareMate'),
      'com.lifemate.caremate://login-callback/',
    );
  });

  test('external auth providers are fail-closed by default', () {
    expect(LifeMateFeatureFlags.googleAuthEnabled, isFalse);
    expect(LifeMateFeatureFlags.phoneOtpEnabled, isFalse);
  });

  test(
    'disabled Google auth returns before creating an OAuth request',
    () async {
      expect(await LifeMateAuth.signInWithGoogle(appName: 'WellMate'), isFalse);
    },
  );

  test('disabled phone auth returns before creating an OTP request', () async {
    await expectLater(
      LifeMateAuth.sendPhoneOtp(
        phoneE164: '09121234567',
        intent: LifeMatePhoneOtpIntent.signIn,
      ),
      throwsA(isA<AuthException>()),
    );
  });

  test('returning phone sign-in never enables implicit user creation', () {
    expect(
      LifeMateAuth.shouldCreatePhoneUser(LifeMatePhoneOtpIntent.signIn),
      isFalse,
    );
    expect(
      LifeMateAuth.shouldCreatePhoneUser(LifeMatePhoneOtpIntent.signUp),
      isTrue,
    );
  });

  test('Iranian mobile variants normalize to one canonical E.164 value', () {
    for (final input in [
      '0912 123 4567',
      '9121234567',
      '+989121234567',
      '989121234567',
      '00989121234567',
      '۰۹۱۲۱۲۳۴۵۶۷',
      '٠٩١٢١٢٣٤٥٦٧',
    ]) {
      expect(LifeMateIranPhone.normalizeE164(input), '+989121234567');
    }
  });

  test('Iranian mobile normalization rejects landline and foreign numbers', () {
    for (final input in [
      '02112345678',
      '+982112345678',
      '+491701234567',
      '0912123456',
      '091212345678',
    ]) {
      expect(
        () => LifeMateIranPhone.normalizeE164(input),
        throwsFormatException,
      );
    }
  });
}
