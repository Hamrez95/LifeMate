import 'package:lifemate_client/lifemate_client.dart';

Future<void> syncOwnerCareEventProjectionsIfSupported({
  required LifeMateApiClient apiClient,
  required Future<void> Function(Set<String> affectedRecordKeys)
  beforeCheckpoint,
}) async {}
