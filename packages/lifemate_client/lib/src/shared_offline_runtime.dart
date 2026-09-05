import 'package:lifemate_core/lifemate_core.dart';

import 'shared_offline_runtime_web.dart'
    if (dart.library.io) 'shared_offline_runtime_native.dart';

export 'shared_offline_runtime_web.dart'
    if (dart.library.io) 'shared_offline_runtime_native.dart';

extension LifeMateOfflineNamespaceLocalMapping on LifeMateOfflineNamespace {
  LifeMateLocalNamespace toLocalNamespace() => LifeMateLocalNamespace(
    environmentId: environmentId,
    accountId: accountId,
    personId: personId,
  );
}
