import 'package:lifemate_core/lifemate_core.dart';

import 'cocoon_pregnancy.dart';
import 'shared_offline_runtime_native.dart' show LifeMateSharedOfflineRuntime;

/// Protected owner-only Cocoon pregnancy projection backed by the shared #829
/// encrypted LifeMate database. It deliberately stores dating inputs, not a
/// mutable current week/day; callers derive gestational age for their local
/// calendar date from the canonical dating basis.
final class CocoonPregnancyOfflineSnapshotCache {
  CocoonPregnancyOfflineSnapshotCache._({
    required LifeMateLocalHealthStore store,
    required LifeMateLocalNamespace namespace,
    required String personId,
    required bool ownsStore,
  }) : _store = store,
       _namespace = namespace,
       _personId = personId,
       _ownsStore = ownsStore;

  static const _recordKey = 'owner-pregnancy-v1';
  static const _payloadVersion = 1;

  final LifeMateLocalHealthStore _store;
  final LifeMateLocalNamespace _namespace;
  final String _personId;
  final bool _ownsStore;
  bool _closed = false;

  static Future<CocoonPregnancyOfflineSnapshotCache> open({
    required LifeMateSharedOfflineRuntime runtime,
    LifeMateLocalHealthStore? store,
    DateTime Function()? now,
  }) async {
    final ownsStore = store == null;
    final localStore = store ?? await LifeMateLocalHealthStore.openDefault(now: now);
    final adopted = runtime.namespace;
    return CocoonPregnancyOfflineSnapshotCache._(
      store: localStore,
      namespace: adopted.toLocalNamespace(),
      personId: adopted.personId,
      ownsStore: ownsStore,
    );
  }

  Future<void> writeCanonicalOwnerSnapshot(
    CocoonPregnancySnapshot snapshot,
  ) async {
    _requireOpen();
    final episode = snapshot.episode;
    if (episode != null && episode.motherPersonId != _personId) {
      throw const CocoonPregnancyOfflineSnapshotScopeException();
    }

    await _store.putProjection(
      namespace: _namespace,
      domain: LifeMateLocalProjectionDomain.pregnancySnapshot,
      recordKey: _recordKey,
      payload: <String, dynamic>{
        'payloadVersion': _payloadVersion,
        'contractVersion': snapshot.contractVersion,
        'episode': episode == null ? null : _encodeEpisode(episode),
      },
      sourceRevision: episode?.version.toString(),
      sourceUpdatedAtUtc: episode?.updatedAtUtc,
      contentVersion: 'cocoon-pregnancy-v${snapshot.contractVersion}',
    );
  }

  Future<CocoonPregnancySnapshot?> readCanonicalOwnerSnapshot() async {
    _requireOpen();
    final record = await _store.readProjection(
      namespace: _namespace,
      domain: LifeMateLocalProjectionDomain.pregnancySnapshot,
      recordKey: _recordKey,
    );
    if (record == null) return null;
    final payload = record.payload;
    if (payload['payloadVersion'] != _payloadVersion) return null;

    final episodeValue = payload['episode'];
    final episode = episodeValue is Map<String, dynamic>
        ? CocoonPregnancyEpisode.fromJson(episodeValue)
        : null;
    if (episode != null && episode.motherPersonId != _personId) {
      throw const CocoonPregnancyOfflineSnapshotScopeException();
    }
    return CocoonPregnancySnapshot(
      contractVersion: (payload['contractVersion'] as num?)?.toInt() ?? 1,
      episode: episode,
    );
  }

  void close() {
    if (_closed) return;
    _closed = true;
    if (_ownsStore) _store.close();
  }

  void _requireOpen() {
    if (_closed) throw StateError('Cocoon offline snapshot cache is closed.');
  }

  static Map<String, dynamic> _encodeEpisode(CocoonPregnancyEpisode episode) {
    final dating = episode.dating;
    return <String, dynamic>{
      'id': episode.id,
      'motherPersonId': episode.motherPersonId,
      'status': _episodeStatus(episode.status),
      'dating': <String, dynamic>{
        'method': dating.method,
        'lmpDate': dating.lmpDate,
        'estimatedDueDate': dating.estimatedDueDate,
        'referenceDate': dating.referenceDate,
        'gestationalAgeAtReferenceDays': dating.gestationalAgeAtReferenceDays,
        // Derived gestationalAge is intentionally omitted. It is recalculated
        // from canonical dating inputs for the caller's current local date.
      },
      'outcome': episode.outcome,
      'activatedAtUtc': episode.activatedAtUtc?.toUtc().toIso8601String(),
      'endedAtUtc': episode.endedAtUtc?.toUtc().toIso8601String(),
      'version': episode.version,
      'updatedAtUtc': episode.updatedAtUtc?.toUtc().toIso8601String(),
    };
  }

  static String _episodeStatus(CocoonPregnancyEpisodeStatus value) =>
      switch (value) {
        CocoonPregnancyEpisodeStatus.draft => 'draft',
        CocoonPregnancyEpisodeStatus.active => 'active',
        CocoonPregnancyEpisodeStatus.ended => 'ended',
        CocoonPregnancyEpisodeStatus.unknown => 'unknown',
      };
}

final class CocoonPregnancyOfflineSnapshotScopeException implements Exception {
  const CocoonPregnancyOfflineSnapshotScopeException();

  @override
  String toString() =>
      'Cocoon pregnancy snapshot does not belong to the adopted Person namespace.';
}
