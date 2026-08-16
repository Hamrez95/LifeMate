import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'feature_flags.dart';
import 'iran_phone.dart';
import 'presentation_numbers.dart';

enum LifeMatePhoneOtpIntent { signIn, signUp }

class LifeMateAuth {
  const LifeMateAuth._();

  static Future<void> signOut() => Supabase.instance.client.auth.signOut();

  static String? get currentAccessToken =>
      Supabase.instance.client.auth.currentSession?.accessToken;

  /// Auth account scope used only to isolate local encrypted queue entries.
  /// It is never persisted as healthcare ownership or a Person identifier.
  static String? get currentAccountId =>
      Supabase.instance.client.auth.currentUser?.id;

  /// Returns an access token that is valid for an immediate authenticated API
  /// call. Supabase Flutter restores a persisted session before an automatic
  /// refresh is guaranteed, which matters for Android widget background
  /// callbacks that may run long after the app was last opened.
  static Future<String?> getValidAccessToken() async {
    final auth = Supabase.instance.client.auth;
    final session = auth.currentSession;
    if (session == null) return null;
    if (!session.isExpired) return session.accessToken;
    final refreshed = await auth.refreshSession();
    return refreshed.session?.accessToken;
  }

  /// Forces a refresh even when the locally restored JWT has not yet crossed
  /// its client-side expiry. This is used by isolated background work after a
  /// server-side 401 so the retried request uses a newly issued token.
  static Future<String?> refreshAccessToken() async {
    final refreshed = await Supabase.instance.client.auth.refreshSession();
    return refreshed.session?.accessToken;
  }

  static String callbackUrlForApp(String appName) {
    final normalized = appName.trim().toLowerCase();
    final scheme = normalized.contains('care')
        ? 'com.lifemate.caremate'
        : 'com.lifemate.wellmate';
    return '$scheme://login-callback/';
  }

  static Future<bool> signInWithGoogle({required String appName}) {
    if (!LifeMateFeatureFlags.googleAuthEnabled) {
      return Future<bool>.value(false);
    }
    return Supabase.instance.client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: kIsWeb ? null : callbackUrlForApp(appName),
      queryParams: const {'prompt': 'select_account'},
    );
  }

  /// Requests a Supabase phone OTP. Delivery is performed server-side by the
  /// configured Send SMS hook (Kavenegar in the Iran deployment).
  ///
  /// Returning-user sign-in is explicitly non-creating so an existing email
  /// account cannot silently become a second Auth/LifeMate identity. New-user
  /// creation is allowed only when the caller explicitly selects [signUp].
  static Future<void> sendPhoneOtp({
    required String phoneE164,
    required LifeMatePhoneOtpIntent intent,
  }) async {
    if (!LifeMateFeatureFlags.phoneOtpEnabled) {
      throw const AuthException('Phone OTP is not enabled for this release.');
    }
    final phone = _normalizeIranPhone(phoneE164);
    await Supabase.instance.client.auth.signInWithOtp(
      phone: phone,
      shouldCreateUser: shouldCreatePhoneUser(intent),
    );
  }

  static bool shouldCreatePhoneUser(LifeMatePhoneOtpIntent intent) =>
      intent == LifeMatePhoneOtpIntent.signUp;

  static Future<AuthResponse> verifyPhoneOtp({
    required String phoneE164,
    required String token,
  }) {
    if (!LifeMateFeatureFlags.phoneOtpEnabled) {
      throw const AuthException('Phone OTP is not enabled for this release.');
    }
    final phone = _normalizeIranPhone(phoneE164);
    final normalizedToken = LifeMateNumbers.toLatin(token).trim();
    if (!RegExp(r'^\d{6,10}$').hasMatch(normalizedToken)) {
      throw const AuthException('OTP format is invalid.');
    }
    return Supabase.instance.client.auth.verifyOTP(
      phone: phone,
      token: normalizedToken,
      type: OtpType.sms,
    );
  }

  /// Starts provider re-authentication for security-sensitive account actions.
  /// Manual identity linking must not be exposed without a verified re-auth
  /// proof in the final provider configuration.
  static Future<void> requestReauthentication() =>
      Supabase.instance.client.auth.reauthenticate();

  static String _normalizeIranPhone(String value) {
    try {
      return LifeMateIranPhone.normalizeE164(value);
    } on FormatException {
      throw const AuthException('Iranian mobile number is invalid.');
    }
  }
}
