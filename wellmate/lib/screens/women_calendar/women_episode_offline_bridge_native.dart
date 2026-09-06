import 'package:lifemate_client/lifemate_client.dart';
import 'package:lifemate_core/lifemate_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final class WomenEpisodeOfflineBridge {
  WomenEpisodeOfflineBridge._(this._runtime, this._outbox);

  final LifeMateSharedOfflineRuntime _runtime;
  final WomenEpisodeOfflineOutbox _outbox;

  static Future<WomenEpisodeOfflineBridge> open({
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
    final localNamespace = LifeMateLocalNamespace(
      environmentId: config.apiBaseUri.toString(),
      accountId: accountId,
      personId: personId,
    );
    final runtime = await LifeMateSharedOfflineRuntime.open(
      namespace: LifeMateOfflineNamespace(
        environmentId: localNamespace.environmentId,
        accountId: localNamespace.accountId,
        personId: localNamespace.personId,
      ),
      timeZone: 'Asia/Tehran',
      apiBaseUri: config.apiBaseUri,
      accessToken: () =>
          Supabase.instance.client.auth.currentSession?.accessToken,
      legacyAccountIds: <String>{legacyAccountId},
    );
    try {
      final outbox = await WomenEpisodeOfflineOutbox.openDefault(
        namespace: localNamespace,
        timeZone: 'Asia/Tehran',
      );
      return WomenEpisodeOfflineBridge._(runtime, outbox);
    } catch (_) {
      runtime.close();
      rethrow;
    }
  }

  Future<void> enqueueCreate({
    required String mutationId,
    required DateTime startedOn,
    DateTime? endedOn,
    String? privateNotes,
  }) => _outbox.enqueueCreate(
    mutationId: mutationId,
    startedOn: startedOn,
    endedOn: endedOn,
    privateNotes: privateNotes,
  );

  Future<void> coalescePendingCreate({
    required String mutationId,
    required DateTime startedOn,
    DateTime? endedOn,
    String? privateNotes,
  }) => _outbox.coalescePendingCreate(
    mutationId: mutationId,
    startedOn: startedOn,
    endedOn: endedOn,
    privateNotes: privateNotes,
  );

  Future<void> enqueueUpdate({
    required String mutationId,
    required String episodeId,
    required int version,
    required DateTime startedOn,
    DateTime? endedOn,
    String? privateNotes,
  }) => _outbox.enqueueUpdate(
    mutationId: mutationId,
    episodeId: episodeId,
    version: version,
    startedOn: startedOn,
    endedOn: endedOn,
    privateNotes: privateNotes,
  );

  Future<List<Map<String, dynamic>>> project(
    Iterable<Map<String, dynamic>> serverEpisodes,
  ) => _outbox.project(serverEpisodes);

  Future<LifeMateOfflineSyncResult> flush() => _runtime.flushDetailed();

  void close() {
    _outbox.close();
    _runtime.close();
  }
}
