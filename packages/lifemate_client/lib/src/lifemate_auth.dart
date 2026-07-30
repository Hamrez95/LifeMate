import 'package:supabase_flutter/supabase_flutter.dart';

class LifeMateAuth {
  const LifeMateAuth._();

  static Future<void> signOut() => Supabase.instance.client.auth.signOut();
}
