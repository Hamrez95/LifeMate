import 'dart:convert';

import 'local_health_store.dart';

/// Health-domain ownership for an offline mutation. Conflict handling is
/// intentionally domain-specific; callers cannot opt into a global LWW mode.
enum LifeMateMutationDomain {
  adherence('adherence'),
  treatment('treatment'),
  careEvent('care_event'),
  womenHealth('women_health'),
  pregnancyDating('pregnancy_dating'),
  healthObservation('health_observation'),
  sharedAuthorization('shared_authorization');

  const LifeMateMutationDomain(this.wireName);

  final String wireName;

  static LifeMateMutationDomain? fromWireName(String value) {
    for (final domain in values) {
      if (domain.wireName == value) return domain;
    }
    return null;
  }
}

enum LifeMateMutationConflictPolicy {
  idempotentLogicalEvent,
  explicitVersionResolution,
  deduplicateAndMerge,
  neverSilentLastWriteWins,
  authorizationFailClosed,
}

enum LifeMateMutationSyncState {
  pending('pending'),
  retryScheduled('retry_scheduled'),
  conflict('conflict'),
  rejected('rejected');

  const LifeMateMutationSyncState(this.wireName);
  final String wireName;

  static LifeMateMutationSyncState? fromWireName(String value) {
    for (final state in values) {
      if (state.wireName == value) return state;
    }
    return null;
  }
}

enum LifeMateMutationErrorClass {
  none('none'),
  transport('transport'),
  authentication('authentication'),
  throttled('throttled'),
  server('server'),
  conflict('conflict'),
  clientRejected('client_rejected'),
  unsafe('unsafe');

  const LifeMateMutationErrorClass(this.wireName);
  final String wireName;

  static LifeMateMutationErrorClass? fromWireName(String value) {
    for (final errorClass in values) {
      if (errorClass.wireName == value) return errorClass;
    }
    return null;
  }
}

LifeMateMutationConflictPolicy lifeMateConflictPolicyFor(
  LifeMateMutationDomain domain,
) => switch (domain) {
  LifeMateMutationDomain.adherence =>
    LifeMateMutationConflictPolicy.idempotentLogicalEvent,
  LifeMateMutationDomain.treatment || LifeMateMutationDomain.careEvent =>
    LifeMateMutationConflictPolicy.explicitVersionResolution,
  LifeMateMutationDomain.womenHealth ||
  LifeMateMutationDomain.healthObservation =>
    LifeMateMutationConflictPolicy.deduplicateAndMerge,
  LifeMateMutationDomain.pregnancyDating =>
    LifeMateMutationConflictPolicy.neverSilentLastWriteWins,
  LifeMateMutationDomain.sharedAuthorization =>
    LifeMateMutationConflictPolicy.authorizationFailClosed,
};

/// Protected, durable mutation envelope stored inside the #829 encrypted local
/// health database. Authentication credentials are deliberately excluded.
final class LifeMateDurableMutation {
  LifeMateDurableMutation({
    required String mutationId,
    required this.domain,
    required String sourceKey,
    required String method,
    required String endpointPath,
    required Map<String, dynamic> payload,
    required this.createdAtUtc,
    required String timeZone,
    this.expectedRevision,
    this.state = LifeMateMutationSyncState.pending,
    this.errorClass = LifeMateMutationErrorClass.none,
    this.attemptCount = 0,
    this.nextAttemptAtUtc,
  }) : mutationId = _require(mutationId, 'mutationId'),
       sourceKey = _require(sourceKey, 'sourceKey'),
       method = _require(method, 'method').toUpperCase(),
       endpointPath = _validateEndpointPath(endpointPath),
       payload = Map<String, dynamic>.unmodifiable(payload),
       timeZone = _require(timeZone, 'timeZone') {
    if (!createdAtUtc.isUtc) {
      throw ArgumentError.value(
        createdAtUtc,
        'createdAtUtc',
        'createdAtUtc must be UTC.',
      );
    }
    if (attemptCount < 0) {
      throw ArgumentError.value(attemptCount, 'attemptCount');
    }
    if (nextAttemptAtUtc != null && !nextAttemptAtUtc!.isUtc) {
      throw ArgumentError.value(
        nextAttemptAtUtc,
        'nextAttemptAtUtc',
        'nextAttemptAtUtc must be UTC.',
      );
    }
  }

  final String mutationId;
  final LifeMateMutationDomain domain;
  final String sourceKey;
  final String method;
  final String endpointPath;
  final Map<String, dynamic> payload;
  final DateTime createdAtUtc;
  final String timeZone;
  final String? expectedRevision;
  final LifeMateMutationSyncState state;
  final LifeMateMutationErrorClass errorClass;
  final int attemptCount;
  final DateTime? nextAttemptAtUtc;

  LifeMateMutationConflictPolicy get conflictPolicy =>
      lifeMateConflictPolicyFor(domain);

  bool isEligibleAt(DateTime nowUtc) {
    if (!nowUtc.isUtc) {
      throw ArgumentError.value(nowUtc, 'nowUtc', 'nowUtc must be UTC.');
    }
    if (state != LifeMateMutationSyncState.pending &&
        state != LifeMateMutationSyncState.retryScheduled) {
      return false;
    }
    return nextAttemptAtUtc == null || !nextAttemptAtUtc!.isAfter(nowUtc);
  }

  LifeMateDurableMutation copyWith({
    LifeMateMutationSyncState? state,
    LifeMateMutationErrorClass? errorClass,
    int? attemptCount,
    DateTime? nextAttemptAtUtc,
    bool clearNextAttempt = false,
  }) => LifeMateDurableMutation(
    mutationId: mutationId,
    domain: domain,
    sourceKey: sourceKey,
    method: method,
    endpointPath: endpointPath,
    payload: payload,
    createdAtUtc: createdAtUtc,
    timeZone: timeZone,
    expectedRevision: expectedRevision,
    state: state ?? this.state,
    errorClass: errorClass ?? this.errorClass,
    attemptCount: attemptCount ?? this.attemptCount,
    nextAttemptAtUtc: clearNextAttempt
        ? null
        : (nextAttemptAtUtc ?? this.nextAttemptAtUtc),
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'version': 1,
    'mutationId': mutationId,
    'domain': domain.wireName,
    'sourceKey': sourceKey,
    'method': method,
    'endpointPath': endpointPath,
    'payload': payload,
    'createdAtUtc': createdAtUtc.toIso8601String(),
    'timeZone': timeZone,
    if (expectedRevision != null && expectedRevision!.trim().isNotEmpty)
      'expectedRevision': expectedRevision!.trim(),
    'state': state.wireName,
    'errorClass': errorClass.wireName,
    'attemptCount': attemptCount,
    if (nextAttemptAtUtc != null)
      'nextAttemptAtUtc': nextAttemptAtUtc!.toIso8601String(),
  };

  static LifeMateDurableMutation fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) {
      throw const FormatException('Unsupported durable mutation version.');
    }
    final domain = LifeMateMutationDomain.fromWireName(
      json['domain']?.toString() ?? '',
    );
    final state = LifeMateMutationSyncState.fromWireName(
      json['state']?.toString() ?? '',
    );
    final errorClass = LifeMateMutationErrorClass.fromWireName(
      json['errorClass']?.toString() ?? '',
    );
    final createdAtUtc = DateTime.tryParse(
      json['createdAtUtc']?.toString() ?? '',
    )?.toUtc();
    final nextAttemptAtUtc = DateTime.tryParse(
      json['nextAttemptAtUtc']?.toString() ?? '',
    )?.toUtc();
    final rawPayload = json['payload'];
    if (domain == null ||
        state == null ||
        errorClass == null ||
        createdAtUtc == null ||
        rawPayload is! Map) {
      throw const FormatException('Invalid durable mutation envelope.');
    }
    return LifeMateDurableMutation(
      mutationId: json['mutationId']?.toString() ?? '',
      domain: domain,
      sourceKey: json['sourceKey']?.toString() ?? '',
      method: json['method']?.toString() ?? '',
      endpointPath: json['endpointPath']?.toString() ?? '',
      payload: <String, dynamic>{
        for (final entry in rawPayload.entries)
          entry.key.toString(): entry.value,
      },
      createdAtUtc: createdAtUtc,
      timeZone: json['timeZone']?.toString() ?? '',
      expectedRevision: json['expectedRevision']?.toString(),
      state: state,
      errorClass: errorClass,
      attemptCount: int.tryParse(json['attemptCount']?.toString() ?? '') ?? 0,
      nextAttemptAtUtc: nextAttemptAtUtc,
    );
  }

  String logicalFingerprint() => jsonEncode(<String, dynamic>{
    'domain': domain.wireName,
    'sourceKey': sourceKey,
    'method': method,
    'endpointPath': endpointPath,
    'payload': payload,
    'expectedRevision': expectedRevision,
  });

  static String _require(String value, String field) {
    final normalized = value.trim();
    if (normalized.isEmpty) throw ArgumentError.value(value, field);
    return normalized;
  }

  static String _validateEndpointPath(String value) {
    final normalized = _require(value, 'endpointPath');
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        !normalized.startsWith('/') ||
        uri.hasScheme ||
        uri.hasAuthority ||
        uri.host.isNotEmpty) {
      throw ArgumentError.value(
        value,
        'endpointPath',
        'Only API-relative paths may be persisted.',
      );
    }
    return normalized;
  }
}

/// Durable outbox backed by the shared protected local database. There is no
/// automatic TTL eviction: once the UI has accepted an owner action it is
/// either acknowledged, retained for retry/conflict resolution, or explicitly
/// rejected. Capacity exhaustion fails before accepting another action.
final class LifeMateLocalMutationOutbox {
  LifeMateLocalMutationOutbox({
    required LifeMateLocalHealthStore store,
    this.maximumItemsPerPerson = 500,
    DateTime Function()? now,
  }) : _store = store,
       _now = now ?? (() => DateTime.now().toUtc()) {
    if (maximumItemsPerPerson <= 0) {
      throw ArgumentError.value(maximumItemsPerPerson, 'maximumItemsPerPerson');
    }
  }

  final LifeMateLocalHealthStore _store;
  final DateTime Function() _now;
  final int maximumItemsPerPerson;

  Future<LifeMateDurableMutation> enqueue({
    required LifeMateLocalNamespace namespace,
    required LifeMateDurableMutation mutation,
  }) async {
    final existing = await _read(namespace, mutation.mutationId);
    if (existing != null) {
      if (existing.logicalFingerprint() != mutation.logicalFingerprint()) {
        throw StateError(
          'A mutation ID cannot be reused for a different logical action.',
        );
      }
      return existing;
    }

    final current = await list(namespace: namespace);
    if (current.length >= maximumItemsPerPerson) {
      throw StateError(
        'LifeMate durable outbox is full; refusing to silently drop an action.',
      );
    }
    await _write(namespace, mutation);
    return mutation;
  }

  Future<List<LifeMateDurableMutation>> list({
    required LifeMateLocalNamespace namespace,
  }) async {
    final records = await _store.listDomain(
      namespace: namespace,
      domain: LifeMateLocalProjectionDomain.pendingMutation,
    );
    final result = <LifeMateDurableMutation>[];
    for (final record in records) {
      try {
        final mutation = LifeMateDurableMutation.fromJson(record.payload);
        if (mutation.mutationId != record.recordKey) {
          throw const FormatException('Mutation key mismatch.');
        }
        result.add(mutation);
      } on FormatException {
        rethrow;
      }
    }
    result.sort((a, b) {
      final byTime = a.createdAtUtc.compareTo(b.createdAtUtc);
      return byTime != 0 ? byTime : a.mutationId.compareTo(b.mutationId);
    });
    return result;
  }

  Future<List<LifeMateDurableMutation>> eligible({
    required LifeMateLocalNamespace namespace,
    DateTime? atUtc,
  }) async {
    final at = (atUtc ?? _now()).toUtc();
    final all = await list(namespace: namespace);
    return all.where((mutation) => mutation.isEligibleAt(at)).toList();
  }

  Future<LifeMateDurableMutation?> get({
    required LifeMateLocalNamespace namespace,
    required String mutationId,
  }) => _read(namespace, mutationId);

  Future<LifeMateDurableMutation> markRetry({
    required LifeMateLocalNamespace namespace,
    required String mutationId,
    required LifeMateMutationErrorClass errorClass,
    Duration? delay,
  }) async {
    if (errorClass != LifeMateMutationErrorClass.transport &&
        errorClass != LifeMateMutationErrorClass.authentication &&
        errorClass != LifeMateMutationErrorClass.throttled &&
        errorClass != LifeMateMutationErrorClass.server) {
      throw ArgumentError.value(errorClass, 'errorClass');
    }
    final current = await _requireMutation(namespace, mutationId);
    final attempts = current.attemptCount + 1;
    final retryDelay = delay ?? retryDelayForAttempt(attempts);
    final next = current.copyWith(
      state: LifeMateMutationSyncState.retryScheduled,
      errorClass: errorClass,
      attemptCount: attempts,
      nextAttemptAtUtc: _now().toUtc().add(retryDelay),
    );
    await _write(namespace, next);
    return next;
  }

  Future<LifeMateDurableMutation> markConflict({
    required LifeMateLocalNamespace namespace,
    required String mutationId,
  }) async {
    final current = await _requireMutation(namespace, mutationId);
    final next = current.copyWith(
      state: LifeMateMutationSyncState.conflict,
      errorClass: LifeMateMutationErrorClass.conflict,
      clearNextAttempt: true,
    );
    await _write(namespace, next);
    return next;
  }

  Future<LifeMateDurableMutation> markRejected({
    required LifeMateLocalNamespace namespace,
    required String mutationId,
    LifeMateMutationErrorClass errorClass =
        LifeMateMutationErrorClass.clientRejected,
  }) async {
    if (errorClass != LifeMateMutationErrorClass.clientRejected &&
        errorClass != LifeMateMutationErrorClass.unsafe) {
      throw ArgumentError.value(errorClass, 'errorClass');
    }
    final current = await _requireMutation(namespace, mutationId);
    final next = current.copyWith(
      state: LifeMateMutationSyncState.rejected,
      errorClass: errorClass,
      clearNextAttempt: true,
    );
    await _write(namespace, next);
    return next;
  }

  /// Acknowledges exactly one logical mutation and removes only that protected
  /// outbox record. The returned envelope can drive a transient "confirmed" UI
  /// state without retaining already-canonical health payloads in the outbox.
  Future<LifeMateDurableMutation?> acknowledge({
    required LifeMateLocalNamespace namespace,
    required String mutationId,
  }) async {
    final current = await _read(namespace, mutationId);
    if (current == null) return null;
    await _store.deleteProjection(
      namespace: namespace,
      domain: LifeMateLocalProjectionDomain.pendingMutation,
      recordKey: current.mutationId,
    );
    return current;
  }

  static Duration retryDelayForAttempt(int attempt) {
    if (attempt <= 0) return Duration.zero;
    const minimum = Duration(seconds: 15);
    const maximum = Duration(minutes: 15);
    var seconds = minimum.inSeconds;
    for (
      var index = 1;
      index < attempt && seconds < maximum.inSeconds;
      index++
    ) {
      seconds *= 2;
    }
    if (seconds > maximum.inSeconds) seconds = maximum.inSeconds;
    return Duration(seconds: seconds);
  }

  Future<LifeMateDurableMutation?> _read(
    LifeMateLocalNamespace namespace,
    String mutationId,
  ) async {
    final normalized = mutationId.trim();
    if (normalized.isEmpty) throw ArgumentError.value(mutationId, 'mutationId');
    final record = await _store.readProjection(
      namespace: namespace,
      domain: LifeMateLocalProjectionDomain.pendingMutation,
      recordKey: normalized,
    );
    if (record == null) return null;
    final mutation = LifeMateDurableMutation.fromJson(record.payload);
    if (mutation.mutationId != record.recordKey) {
      throw const FormatException('Mutation key mismatch.');
    }
    return mutation;
  }

  Future<LifeMateDurableMutation> _requireMutation(
    LifeMateLocalNamespace namespace,
    String mutationId,
  ) async {
    final mutation = await _read(namespace, mutationId);
    if (mutation == null) {
      throw StateError('Durable mutation is not present in the local outbox.');
    }
    return mutation;
  }

  Future<void> _write(
    LifeMateLocalNamespace namespace,
    LifeMateDurableMutation mutation,
  ) => _store.putProjection(
    namespace: namespace,
    domain: LifeMateLocalProjectionDomain.pendingMutation,
    recordKey: mutation.mutationId,
    payload: mutation.toJson(),
    sourceRevision: mutation.expectedRevision,
    sourceUpdatedAtUtc: mutation.createdAtUtc,
  );
}
