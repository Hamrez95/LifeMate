import 'package:supabase_flutter/supabase_flutter.dart';

import 'account_security.dart';

LifeMateAccountSecurityController lifeMateAccountSecurityControllerForApp(
  String appName,
) =>
    LifeMateAccountSecurityController.supabase(
      client: Supabase.instance.client,
      appName: appName,
    );
