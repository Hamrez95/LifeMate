import 'local_health_store.dart';

/// Server-issued progress marker for one bounded projection domain.
///
/// The checkpoint is stored inside the same encrypted Account + Person +
/// environment database as health projections. It is advisory local execution
/// state only; server data remains canonical.
final class LifeMateLocalSyncCheckpoint {
  const LifeMateLocalSyncCheckpoint({
    required this.domain,
    required this.cursor,
    required this.storedAtUtc,
    this.serverUpdatedAtUtc,
    this.sourceRevision,
  });

  final LifeMateLocalProjectionDomain domain;
  final String cursor;
  final DateTime storedAtUtc;
  final DateTime? serverUpdatedAtUtc;
  final String? sourceRevision;
}

/// Persists incremental-pull checkpoints without creating a second local DB or
/// exposing raw Account/Person/domain identifiers outside the protected store.
final class LifeMateLocalSyncCheckpointStore {
  const LifeMateLocalSyncCheckpointStore(this._store);

  static const _formatVersion = 1;

  final LifeMateLocalHealthStore _store;

  Future<void> write({
    required LifeMateLocalNamespace namespace,
    required LifeMateLocalProjectionDomain domain,
    required String cursor,
    DateTime? serverUpdatedAtUtc,
    String? sourceRevision,
  }) async {
    _requireTargetDomain(domain);
    final normalizedCursor = cursor.trim();
    if (normalizedCursor.isEmpty || normalizedCursor.length > 2048) {
      throw ArgumentError.value(cursor, 'cursor', 'Invalid sync cursor.');
    }
    await _store.putProjection(
      namespace: namespace,
      domain: LifeMateLocalProjectionDomain.syncMetadata,
      recordKey: domain.wireName,
      payload: <String, dynamic>{
        'formatVersion': _formatVersion,
        'targetDomain': domain.wireName,
        'cursor': normalizedCursor,
      },
      sourceRevision: _nullable(sourceRevision),
      sourceUpdatedAtUtc: serverUpdatedAtUtc?.toUtc(),
      syncCursor: normalizedCursor,
    );
  }

  Future<LifeMateLocalSyncCheckpoint?> read({
    required LifeMateLocalNamespace namespace,
    required LifeMateLocalProjectionDomain domain,
  }) async {
    _requireTargetDomain(domain);
    final record = await _store.readProjection(
      namespace: namespace,
      domain: LifeMateLocalProjectionDomain.syncMetadata,
      recordKey: domain.wireName,
    );
    if (record == null) return null;

    final payload = record.payload;
    if (payload['formatVersion'] != _formatVersion ||
        payload['targetDomain'] != domain.wireName) {
      throw const LifeMateLocalStoreCorruptionException();
    }
    final cursor = payload['cursor']?.toString().trim() ?? '';
    if (cursor.isEmpty || cursor != record.syncCursor) {
      throw const LifeMateLocalStoreCorruptionException();
    }
    return LifeMateLocalSyncCheckpoint(
      domain: domain,
      cursor: cursor,
      storedAtUtc: record.storedAtUtc,
      serverUpdatedAtUtc: record.sourceUpdatedAtUtc,
      sourceRevision: record.sourceRevision,
    );
  }

  Future<void> clear({
    required LifeMateLocalNamespace namespace,
    required LifeMateLocalProjectionDomain domain,
  }) async {
    _requireTargetDomain(domain);
    await _store.deleteProjection(
      namespace: namespace,
      domain: LifeMateLocalProjectionDomain.syncMetadata,
      recordKey: domain.wireName,
    );
  }

  static void _requireTargetDomain(LifeMateLocalProjectionDomain domain) {
    if (domain == LifeMateLocalProjectionDomain.syncMetadata ||
        domain == LifeMateLocalProjectionDomain.pendingMutation ||
        domain == LifeMateLocalProjectionDomain.notificationSchedule) {
      throw ArgumentError.value(
        domain,
        'domain',
        'Sync checkpoints are only valid for server projection domains.',
      );
    }
  }

  static String? _nullable(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
