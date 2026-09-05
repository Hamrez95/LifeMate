/// Platform-neutral projection contracts exposed to web builds.
///
/// The protected SQLite-backed health execution engine is intentionally absent
/// on web. These value types keep shared API/UI code compilable without
/// introducing an unreviewed browser PHI store.
enum LifeMateLocalProjectionDomain {
  treatmentPlan('treatment_plan'),
  treatmentOccurrence('treatment_occurrence'),
  careEvent('care_event'),
  womenHealthCycle('women_health_cycle'),
  pregnancySnapshot('pregnancy_snapshot'),
  pregnancyContent('pregnancy_content'),
  healthObservation('health_observation'),
  pendingMutation('pending_mutation'),
  notificationSchedule('notification_schedule'),
  syncMetadata('sync_metadata');

  const LifeMateLocalProjectionDomain(this.wireName);

  final String wireName;
}

/// Type-compatible namespace for shared APIs compiled on web.
///
/// Browser builds may carry these identifiers in memory for request/projection
/// wiring, but the web seam does not provide any protected local persistence.
final class LifeMateLocalNamespace {
  LifeMateLocalNamespace({
    required String environmentId,
    required String accountId,
    required String personId,
  }) : environmentId = _requireValue(environmentId, 'environmentId'),
       accountId = _requireValue(accountId, 'accountId'),
       personId = _requireValue(personId, 'personId');

  final String environmentId;
  final String accountId;
  final String personId;

  static String _requireValue(String value, String field) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(value, field, '$field must not be empty.');
    }
    return normalized;
  }
}

/// Web-visible projection value with the same read-only shape as the native
/// record. Web runtime methods still fail closed before any protected health
/// projection can be persisted or returned from browser storage.
final class LifeMateLocalProjectionRecord {
  const LifeMateLocalProjectionRecord({
    required this.domain,
    required this.recordKey,
    required this.payload,
    required this.storedAtUtc,
    this.sourceRevision,
    this.sourceUpdatedAtUtc,
    this.syncCursor,
    this.contentVersion,
    this.ruleVersion,
  });

  final LifeMateLocalProjectionDomain domain;
  final String recordKey;
  final Map<String, dynamic> payload;
  final DateTime storedAtUtc;
  final String? sourceRevision;
  final DateTime? sourceUpdatedAtUtc;
  final String? syncCursor;
  final String? contentVersion;
  final String? ruleVersion;
}

/// Type-only web seam for APIs whose native signature accepts the protected
/// local health store. There is intentionally no constructor or implementation
/// on web, so browser code cannot instantiate the native encrypted execution
/// engine or silently substitute an unprotected PHI store.
abstract interface class LifeMateLocalHealthStore {
  Future<void> putProjection({
    required LifeMateLocalNamespace namespace,
    required LifeMateLocalProjectionDomain domain,
    required String recordKey,
    required Map<String, dynamic> payload,
    String? sourceRevision,
    DateTime? sourceUpdatedAtUtc,
    String? syncCursor,
    String? contentVersion,
    String? ruleVersion,
  });

  Future<LifeMateLocalProjectionRecord?> readProjection({
    required LifeMateLocalNamespace namespace,
    required LifeMateLocalProjectionDomain domain,
    required String recordKey,
  });
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

/// Web-visible value type matching the native deterministic Women Health
/// pending-overlay result. The browser runtime still fails closed before any
/// protected health mutation/projection persistence; this type only keeps
/// conditional shared APIs source-compatible for web compilation.
final class LifeMateWomenDailyLogProjectionResult {
  const LifeMateWomenDailyLogProjectionResult({
    required this.rows,
    required this.pendingDates,
    required this.pendingDeletedDates,
    required this.conflictDates,
  });

  final List<Map<String, dynamic>> rows;
  final Set<String> pendingDates;
  final Set<String> pendingDeletedDates;
  final Set<String> conflictDates;

  bool get hasPending => pendingDates.isNotEmpty;
  bool get hasConflict => conflictDates.isNotEmpty;
}
