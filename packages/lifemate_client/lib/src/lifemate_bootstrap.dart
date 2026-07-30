import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config.dart';

class LifeMateBootstrap {
  const LifeMateBootstrap._();

  static Future<bool> initialize(AppConfig config) async {
    if (!config.isConfigured) return false;
    await Supabase.initialize(
      url: config.supabaseUrl,
      publishableKey: config.supabasePublishableKey,
    );
    return true;
  }
}
