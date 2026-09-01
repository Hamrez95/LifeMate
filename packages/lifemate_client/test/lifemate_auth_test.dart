import 'dart:io';

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

  test('Supabase SMS resend cooldown is recognized without exposing raw copy', () {
    expect(
      LifeMateAuth.isPhoneOtpSendRateLimited(
        const AuthException('over_sms_send_rate_limit'),
      ),
      isTrue,
    );
    expect(
      LifeMateAuth.isPhoneOtpSendRateLimited(
        const AuthException(
          'For security purposes, you can only request this after 60 seconds.',
        ),
      ),
      isTrue,
    );
  });

  test('broader quota errors are not treated as proof an OTP was sent', () {
    expect(
      LifeMateAuth.isPhoneOtpSendRateLimited(
        const AuthException('Daily provider quota limit exceeded.'),
      ),
      isFalse,
    );
    expect(
      LifeMateAuth.isPhoneOtpSendRateLimited(
        const AuthException('Too many authentication attempts.'),
      ),
      isFalse,
    );
  });

  test('OTP cooldown recovery never schedules a background resend', () {
    final source = File('lib/src/lifemate_auth.dart').readAsStringSync();
    expect(
      source,
      contains('if (isPhoneOtpSendRateLimited(error)) return;'),
    );
    expect(source, isNot(contains('Timer(')));
    expect(source, isNot(contains('Future.delayed')));
  });

  test('shared auth keeps the server-aligned 60 second resend gate localized', () {
    final uiSource = File(
      '../lifemate_ui/lib/src/shared_auth_experience.dart',
    ).readAsStringSync();

    expect(uiSource, contains('static const _resendDelaySeconds = 60;'));
    expect(
      uiSource,
      contains('final canResend = _resendSeconds == 0 && !_busy;'),
    );
    expect(uiSource, contains('_startResendCountdown();'));
    expect(uiSource, contains("fa: 'ارسال مجدد تا \$_resendSeconds ثانیه'"));
    expect(uiSource, contains("en: 'Resend in \$_resendSeconds s'"));

    final countdownStart = uiSource.indexOf('void _startResendCountdown()');
    final googleStart = uiSource.indexOf(
      'Future<void> _signInWithGoogle()',
      countdownStart,
    );
    expect(countdownStart, greaterThanOrEqualTo(0));
    expect(googleStart, greaterThan(countdownStart));
    final countdownBody = uiSource.substring(countdownStart, googleStart);
    expect(countdownBody, isNot(contains('_sendPhoneCode')));
  });
}