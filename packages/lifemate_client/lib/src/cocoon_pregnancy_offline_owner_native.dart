import 'package:lifemate_core/lifemate_core.dart';

import 'capabilities.dart';
import 'cocoon_pregnancy.dart';
import 'cocoon_pregnancy_offline_snapshot_native.dart';
import 'lifemate_api_client.dart' show AccessTokenProvider;
import 'offline_identity_adoption_native.dart';
import 'offline_mutation_queue.dart' show LifeMateMutationStorage;
import 'shared_offline_runtime_native.dart';

typedef CocoonCanonicalIdentityResolver =
    Future<LifeMateCapabilitySnapshot> Function();

/// Bridges an authoritative Cocoon bootstrap to the protected owner-only local
/// pregnancy projection and reopens that projection after a process restart.
///
/// The secure adopted identity is a lookup key only. It never grants current
/// entitlement, relationship/sharing access, or permission to mutate server
/// state while offline.
final class CocoonPregnancyOfflineOwnerCoordinator {
  CocoonPregnancyOfflineOwnerCoordinator({
    required this.apiBaseUri,
    required String legacyAccountId,
    required this.accessToken,
    required this.identityResolver,
    LifeMateOfflineIdentityAdoptionStore? identityStore,
    LifeMateLocalHealthStore? localStore,
    LifeMateMutationStorage? legacyStorage,
    String timeZone = 'Asia/Tehran',
  }) : legacyAccountId = _required(legacyAccountId, 'legacyAccountId'),
       timeZone = _required(timeZone, 'timeZone'),
       _identityStore =
           identityStore ?? LifeMateOfflineIdentityAdoptionStore.secure(),
       _localStore = localStore,
       _legacyStorage = legacyStorage;

  final Uri apiBaseUri;
  final String legacyAccountId;
  final AccessTokenProvider accessToken;
  final CocoonCanonicalIdentityResolver identityResolver;
  final String timeZone;
  final LifeMateOfflineIdentityAdoptionStore _identityStore;
  final LifeMateLocalHealthStore? _localStore;
  final LifeMateMutationStorage? _legacyStorage;

  String get _environmentId => apiBaseUri.toString();

  /// Called only after a server-authoritative Cocoon bootstrap succeeds.
  /// If the server no longer permits owner cached snapshots, the persisted
  /// identity lookup is revoked so a later restart cannot reopen stale Cocoon
  /// owner data through this coordinator.
  Future<void> cacheAuthoritativeBootstrap(
    CocoonBootstrapSnapshot bootstrap,
  ) async {
    if (!bootstrap.cachedOwnerSnapshotAllowed) {
      await _identityStore.forget(
        environmentId: _environmentId,
        legacyAccountId: legacyAccountId,
      );
      return;
    }

    final personId = _required(bootstrap.personId, 'bootstrap.personId');
    final capabilities = await identityResolver();
    final canonicalPersonId = capabilities.selfPersonId?.trim();
    if (canonicalPersonId == null ||
        canonicalPersonId.isEmpty ||
        canonicalPersonId != personId) {
      throw const CocoonOfflineOwnerIdentityMismatchException();
    }

    await _identityStore.remember(
      environmentId: _environmentId,
      legacyAccountId: legacyAccountId,
      accountId: capabilities.accountId,
      personId: canonicalPersonId,
    );
    final adoption = await _identityStore.lookup(
      environmentId: _environmentId,
      legacyAccountId: legacyAccountId,
    );
    if (adoption == null) {
      throw StateError('Cocoon offline owner identity was not persisted.');
    }

    await _withSnapshotCache<void>(adoption, (cache) {
      return cache.writeCanonicalOwnerSnapshot(
        CocoonPregnancySnapshot(
          contractVersion: bootstrap.contractVersion,
          episode: bootstrap.activeEpisode,
        ),
      );
    });
  }

  /// Reads only the previously cached owner projection. No network identity,
  /// entitlement, relationship or sharing lookup is attempted here.
  Future<CocoonPregnancySnapshot?> readCachedOwnerSnapshot() async {
    final adoption = await _identityStore.lookup(
      environmentId: _environmentId,
      legacyAccountId: legacyAccountId,
    );
    if (adoption == null) return null;
    return _withSnapshotCache<CocoonPregnancySnapshot?>(
      adoption,
      (cache) => cache.readCanonicalOwnerSnapshot(),
    );
  }

  Future<void> forgetAdoptedOwner() => _identityStore.forget(
    environmentId: _environmentId,
    legacyAccountId: legacyAccountId,
  );

  Future<T> _withSnapshotCache<T>(
    LifeMateOfflineIdentityAdoption adoption,
    Future<T> Function(CocoonPregnancyOfflineSnapshotCache cache) action,
  ) async {
    final ownsStore = _localStore == null;
    final store = _localStore ?? await LifeMateLocalHealthStore.openDefault();
    LifeMateSharedOfflineRuntime? runtime;
    CocoonPregnancyOfflineSnapshotCache? cache;
    try {
      runtime = await LifeMateSharedOfflineRuntime.open(
        namespace: adoption.toLocalNamespace(),
        timeZone: timeZone,
        apiBaseUri: apiBaseUri,
        accessToken: accessToken,
        legacyAccountIds: <String>{legacyAccountId},
        store: store,
        legacyStorage: _legacyStorage,
      );
      cache = await CocoonPregnancyOfflineSnapshotCache.open(
        runtime: runtime,
        store: store,
      );
      return await action(cache);
    } finally {
      cache?.close();
      runtime?.close();
      if (ownsStore) store.close();
    }
  }

  static String _required(String value, String field) {
    final normalized = value.trim();
    if (normalized.isEmpty) throw ArgumentError.value(value, field);
    return normalized;
  }
}

final class CocoonOfflineOwnerIdentityMismatchException implements Exception {
  const CocoonOfflineOwnerIdentityMismatchException();

  @override
  String toString() =>
      'Cocoon bootstrap Person does not match the canonical authenticated Person.';
}
