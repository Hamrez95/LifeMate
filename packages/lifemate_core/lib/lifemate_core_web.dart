/// Platform-neutral projection contracts exposed to web builds.
///
/// The protected SQLite-backed health execution engine is intentionally absent
/// on web. These value types keep shared API/UI code compilable without
/// introducing an unreviewed browser PHI store.
enum LifeMateLocalProjectionDomain {
  careEvent('care_event'),
  medication('medication'),
  treatment('treatment'),
  appointment('appointment'),
  syncMetadata('sync_metadata'),
  pendingMutation('pending_mutation'),
  notificationSchedule('notification_schedule');

  const LifeMateLocalProjectionDomain(this.wireName);

  final String wireName;
}

final class LifeMateServerProjectionChange {
  LifeMateServerProjectionChange.upsert({
    required String recordKey,
    required Map<String, dynamic> payload,
    String? sourceRevision,
    DateTime? sourceUpdatedAtUtc,
  }) : recordKey = recordKey,
       payload = Map<String, dynamic>.unmodifiable(payload),
       sourceRevision = sourceRevision,
       sourceUpdatedAtUtc = sourceUpdatedAtUtc?.toUtc(),
       deleted = false;

  LifeMateServerProjectionChange.delete({
    required String recordKey,
    String? sourceRevision,
    DateTime? sourceUpdatedAtUtc,
  }) : recordKey = recordKey,
       payload = null,
       sourceRevision = sourceRevision,
       sourceUpdatedAtUtc = sourceUpdatedAtUtc?.toUtc(),
       deleted = true;

  final String recordKey;
  final Map<String, dynamic>? payload;
  final String? sourceRevision;
  final DateTime? sourceUpdatedAtUtc;
  final bool deleted;
}

final class LifeMateProjectionPullPage {
  LifeMateProjectionPullPage({
    required this.nextCursor,
    required Iterable<LifeMateServerProjectionChange> changes,
    this.hasMore = false,
    this.serverUpdatedAtUtc,
    this.sourceRevision,
  }) : changes = List<LifeMateServerProjectionChange>.unmodifiable(changes);

  final String nextCursor;
  final List<LifeMateServerProjectionChange> changes;
  final bool hasMore;
  final DateTime? serverUpdatedAtUtc;
  final String? sourceRevision;
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

typedef LifeMateBeforeProjectionCheckpoint =
    Future<void> Function(LifeMateProjectionReconcileResult stagedResult);

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
