import 'package:lifemate_client/lifemate_client.dart';
import 'package:lifemate_core/lifemate_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final class WomenDailyLogOfflineBridge {
  WomenDailyLogOfflineBridge._(this._runtime);

  final LifeMateSharedOfflineRuntime _runtime;

  static Future<WomenDailyLogOfflineBridge> open({
    required LifeMateApiClient apiClient,
  }) async {
    final session = Supabase.instance.client.auth.currentSession;
    final legacyAccountId = session?.user.id.trim();
    if (legacyAccountId == null || legacyAccountId.isEmpty) {
      throw const LifeMateApiException(
        statusCode: 401,
        code: 'offline_identity_unavailable',
        message: 'Authenticated identity is unavailable for offline runtime.',
      );
    }

    final capabilities = await apiClient.getCapabilities();
    final personId = capabilities.selfPersonId?.trim();
    final accountId = capabilities.accountId.trim();
    if (personId == null || personId.isEmpty || accountId.isEmpty) {
      throw const LifeMateApiException(
        statusCode: 409,
        code: 'identity_person_mapping_missing',
        message: 'The LifeMate person mapping is unavailable.',
      );
    }

    final config = AppConfig.fromEnvironment();
    final runtime = await LifeMateSharedOfflineRuntime.open(
      namespace: LifeMateOfflineNamespace(
        environmentId: config.apiBaseUri.toString(),
        accountId: accountId,
        personId: personId,
      ),
      timeZone: 'Asia/Tehran',
      apiBaseUri: config.apiBaseUri,
      accessToken: () => Supabase.instance.client.auth.currentSession?.accessToken,
      legacyAccountIds: <String>{legacyAccountId},
    );
    return WomenDailyLogOfflineBridge._(runtime);
  }

  Future<LifeMateWomenDailyLogProjectionResult> project({
    required Iterable<Map<String, dynamic>> serverRows,
    required DateTime fromDate,
    required DateTime toDate,
  }) => _runtime.projectWomenDailyLogs(
    serverRows: serverRows,
    fromDate: fromDate,
    toDate: toDate,
  );

  Future<void> enqueueUpsert({
    required String mutationId,
    required DateTime loggedOn,
    required int version,
    String? periodFlow,
    String? bloodAppearance,
    String? bloodTexture,
    int? painLevel,
    Set<String> symptoms = const <String>{},
    String? privateNotes,
  }) => _runtime.enqueueWomenDailyLogUpsert(
    mutationId: mutationId,
    loggedOn: loggedOn,
    version: version,
    periodFlow: periodFlow,
    bloodAppearance: bloodAppearance,
    bloodTexture: bloodTexture,
    painLevel: painLevel,
    symptoms: symptoms,
    privateNotes: privateNotes,
  );

  Future<LifeMateOfflineSyncResult> flush() => _runtime.flushDetailed();

  void close() => _runtime.close();
}
