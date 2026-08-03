import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LifeMateAuth {
  const LifeMateAuth._();

  static Future<void> signOut() => Supabase.instance.client.auth.signOut();

  static String callbackUrlForApp(String appName) {
    final normalized = appName.trim().toLowerCase();
    final scheme = normalized.contains('care')
        ? 'com.lifemate.caremate'
        : 'com.lifemate.wellmate';
    return '$scheme://login-callback/';
  }

  static Future<bool> signInWithGoogle({required String appName}) {
    return Supabase.instance.client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: kIsWeb ? null : callbackUrlForApp(appName),
      queryParams: const {
        'prompt': 'select_account',
      },
    );
  }
}
