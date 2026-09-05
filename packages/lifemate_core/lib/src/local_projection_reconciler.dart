import 'local_health_store.dart';
import 'local_sync_checkpoint.dart';

/// One server-authoritative projection change from an incremental pull page.
/// A tombstone deletes only the addressed server projection record; local-only
/// mutation/reminder domains are never accepted by the reconciler.
final class LifeMateServerProjectionChange {
  LifeMateServerProjectionChange.upsert({
    required String recordKey,
    required Map<String, dynamic> payload,
    String? sourceRevision,
    DateTime? sourceUpdatedAtUtc,
  }) : recordKey = _required(recordKey, 'recordKey'),
       payload = Map<String, dynamic>.unmodifiable(payload),
       sourceRevision = _nullable(sourceRevision),
       sourceUpdatedAtUtc = sourceUpdatedAtUtc?.toUtc(),
       deleted = false;

  LifeMateServerProjectionChange.delete({
    required String recordKey,
    String? sourceRevision,
    DateTime? sourceUpdatedAtUtc,
  }) : recordKey = _required(recordKey, 'recordKey'),
       payload = null,
       sourceRevision = _nullable(sourceRevision),
       sourceUpdatedAtUtc = sourceUpdatedAtUtc?.toUtc(),
       deleted = true;

  final String recordKey;
  final Map<String, dynamic>? payload;
  final String? sourceRevision;
  final DateTime? sourceUpdatedAtUtc;
  final bool deleted;

  static String _required(String value, String field) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized.length > 512) {
      throw ArgumentError.value(value, field);
    }
    return normalized;
  }

  static String? _nullable(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}

final class LifeMateProjectionPullPage {
  LifeMateProjectionPullPage({
    required String nextCursor,
    required Iterable<LifeMateServerProjectionChange> changes,
    this.serverUpdatedAtUtc,
    this.sourceRevision,
  }) : nextCursor = _requiredCursor(nextCursor),
       changes = List<LifeMateServerProjectionChange>.unmodifiable(changes);

  final String nextCursor;
  final List<LifeMateServerProjectionChange> changes;
  final DateTime? serverUpdatedAtUtc;
  final String? sourceRevision;

  static String _requiredCursor(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized.length > 2048) {
      throw ArgumentError.value(value, 'nextCursor', 'Invalid sync cursor.');
    }
    return normalized;
  }
}

final class LifeMateProjectionReconcileResult {
  const LifeMateProjectionReconcileResult({
    required this.applied,
    required this.deleted,
    required this.affectedRecordKeys,
    required this.nextCursor,
  });

  final int applied;
  final int deleted;
  final Set<String> affectedRecordKeys;
  final String nextCursor;
}

/// Applies server pull pages idempotently, then advances the encrypted cursor
/// only after every projection mutation has completed successfully.
///
/// If a process dies mid-page, some upserts may already be present but the old
/// checkpoint is retained. Replaying the same server page is safe because
/// projection writes are keyed upserts/deletes. Pending local mutations and
/// notification schedules live in separate domains and are never replaced.
final class LifeMateLocalProjectionReconciler {
  LifeMateLocalProjectionReconciler({
    required LifeMateLocalHealthStore store,
    LifeMateLocalSyncCheckpointStore? checkpoints,
  }) : _store = store,
       _checkpoints = checkpoints ?? LifeMateLocalSyncCheckpointStore(store);

  final LifeMateLocalHealthStore _store;
  final LifeMateLocalSyncCheckpointStore _checkpoints;

  Future<LifeMateProjectionReconcileResult> applyPage({
    required LifeMateLocalNamespace namespace,
    required LifeMateLocalProjectionDomain domain,
    required LifeMateProjectionPullPage page,
  }) async {
    _requireServerDomain(domain);
    var applied = 0;
    var deleted = 0;
    final affected = <String>{};

    for (final change in page.changes) {
      if (change.deleted) {
        await _store.deleteProjection(
          namespace: namespace,
          domain: domain,
          recordKey: change.recordKey,
        );
        deleted += 1;
      } else {
        await _store.putProjection(
          namespace: namespace,
          domain: domain,
          recordKey: change.recordKey,
          payload: change.payload!,
          sourceRevision: change.sourceRevision,
          sourceUpdatedAtUtc: change.sourceUpdatedAtUtc,
          syncCursor: page.nextCursor,
        );
        applied += 1;
      }
      affected.add(change.recordKey);
    }

    // Cursor advancement is the final acknowledgement. Any error above leaves
    // the previous checkpoint intact so the page can be replayed after restart.
    await _checkpoints.write(
      namespace: namespace,
      domain: domain,
      cursor: page.nextCursor,
      serverUpdatedAtUtc: page.serverUpdatedAtUtc,
      sourceRevision: page.sourceRevision,
    );

    return LifeMateProjectionReconcileResult(
      applied: applied,
      deleted: deleted,
      affectedRecordKeys: Set<String>.unmodifiable(affected),
      nextCursor: page.nextCursor,
    );
  }

  Future<LifeMateLocalSyncCheckpoint?> checkpoint({
    required LifeMateLocalNamespace namespace,
    required LifeMateLocalProjectionDomain domain,
  }) => _checkpoints.read(namespace: namespace, domain: domain);

  static void _requireServerDomain(LifeMateLocalProjectionDomain domain) {
    if (domain == LifeMateLocalProjectionDomain.syncMetadata ||
        domain == LifeMateLocalProjectionDomain.pendingMutation ||
        domain == LifeMateLocalProjectionDomain.notificationSchedule) {
      throw ArgumentError.value(
        domain,
        'domain',
        'Projection reconciliation is only valid for server domains.',
      );
    }
  }
}
