import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config.dart';
import 'secure_session_storage.dart';

class LifeMateBootstrap {
  const LifeMateBootstrap._();

  static Future<bool> initialize(AppConfig config) async {
    if (!config.isConfigured) return false;

    final useSecureMobileStorage =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);

    await Supabase.initialize(
      url: config.supabaseUrl,
      publishableKey: config.supabasePublishableKey,
      authOptions: FlutterAuthClientOptions(
        // This task intentionally changes Android/iOS persistence only. Keep
        // Supabase's established web/desktop storage behavior unchanged.
        localStorage: useSecureMobileStorage
            ? LifeMateSecureSessionStorage.forSupabaseUrl(config.supabaseUrl)
            : null,
      ),
    );
    return true;
  }
}
