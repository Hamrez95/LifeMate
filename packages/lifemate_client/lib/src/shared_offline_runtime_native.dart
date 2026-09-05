import 'package:http/http.dart' as http;
import 'package:lifemate_core/lifemate_core.dart';

import 'legacy_mutation_importer.dart';
import 'lifemate_api_client.dart' show AccessTokenProvider;
import 'mutation_replay_transport.dart';
import 'offline_mutation_queue.dart' show LifeMateMutationStorage;
import 'offline_sync_result.dart';

final class LifeMateLocalDataPurgeConfirmationRequiredException
    implements Exception {
  const LifeMateLocalDataPurgeConfirmationRequiredException();

  @override
  String toString() =>
      'LifeMate local account purge requires explicit destructive confirmation.';
}

final class LifeMateOfflineNamespace {
  LifeMateOfflineNamespace({
    required String environmentId,
    required String accountId,
    required String personId,
  }) : environmentId = _required(environmentId, 'environmentId'),
       accountId = _required(accountId, 'accountId'),
       personId = _required(personId, 'personId');

  final String environmentId;
  final String accountId;
  final String personId;

  LifeMateLocalNamespace toLocalNamespace() => LifeMateLocalNamespace(
    environmentId: environmentId,
    accountId: accountId,
    personId: personId,
  );

  static LifeMateOfflineNamespace fromLocal(LifeMateLocalNamespace value) =>
      LifeMateOfflineNamespace(
        environmentId: value.environmentId,
        accountId: value.accountId,
        personId: value.personId,
      );

  static String _required(String value, String field) {
    final normalized = value.trim();
    if (normalized.isEmpty) throw ArgumentError.value(value, field);
    return normalized;
  }
}

/// Native shared #829/#831 protected local store, replay and server-projection
/// reconciliation runtime. Owner projections and pending local mutations share
/// one encrypted namespace while remaining in separate bounded domains.
final class LifeMateSharedOfflineRuntime {
  LifeMateSharedOfflineRuntime._({
    required LifeMateLocalHealthStore store,
    required LifeMateOfflineNamespace namespace,
    required LifeMateLocalNamespace localNamespace,
    required LifeMateLocalMutationOutbox outbox,
    required LifeMateLocalMutationReplayEngine replayEngine,
    required LifeMateLocalProjectionReconciler projectionReconciler,
    required LifeMateHttpMutationReplayTransport transport,
    required LifeMateLegacyMutationImporter legacyImporter,
    required String timeZone,
    required Set<String> legacyAccountIds,
    required bool ownsStore,
  }) : _store = store,
       _namespace = namespace,
       _localNamespace = localNamespace,
       _outbox = outbox,
       _replayEngine = replayEngine,
       _projectionReconciler = projectionReconciler,
       _transport = transport,
       _legacyImporter = legacyImporter,
       _timeZone = timeZone,
       _legacyAccountIds = Set<String>.unmodifiable(legacyAccountIds),
       _ownsStore = ownsStore;

  static const _wellMateHomeMarkerKey = 'wellmate-home-window-v1';

  final LifeMateLocalHealthStore _store;
  final LifeMateOfflineNamespace _namespace;
  final LifeMateLocalNamespace _localNamespace;
  final LifeMateLocalMutationOutbox _outbox;
  final LifeMateLocalMutationReplayEngine _replayEngine;
  final LifeMateLocalProjectionReconciler _projectionReconciler;
  final LifeMateHttpMutationReplayTransport _transport;
  final LifeMateLegacyMutationImporter _legacyImporter;
  final String _timeZone;
  final Set<String> _legacyAccountIds;
  final bool _ownsStore;
  bool _closed = false;
  bool _accountPurged = false;

  LifeMateOfflineNamespace get namespace => _namespace;

  static Future<LifeMateSharedOfflineRuntime> open({
    required Object namespace,
    required String timeZone,
    required Uri apiBaseUri,
    required AccessTokenProvider accessToken,
    Set<String> legacyAccountIds = const <String>{},
    LifeMateLocalHealthStore? store,
    LifeMateMutationStorage? legacyStorage,
    http.Client? httpClient,
    int maximumMutationsPerRun = 25,
    DateTime Function()? now,
  }) async {
    final offlineNamespace = switch (namespace) {
      LifeMateOfflineNamespace value => value,
      LifeMateLocalNamespace value => LifeMateOfflineNamespace.fromLocal(value),
      _ => throw ArgumentError.value(namespace, 'namespace'),
    };
    final localNamespace = offlineNamespace.toLocalNamespace();
    final normalizedTimeZone = timeZone.trim();
    if (normalizedTimeZone.isEmpty) {
      throw ArgumentError.value(timeZone, 'timeZone');
    }
    final normalizedLegacyAccountIds = legacyAccountIds
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();

    final ownsStore = store == null;
    final localStore =
        store ?? await LifeMateLocalHealthStore.openDefault(now: now);
    final outbox = LifeMateLocalMutationOutbox(store: localStore, now: now);
    final transport = LifeMateHttpMutationReplayTransport(
      apiBaseUri: apiBaseUri,
      accessToken: accessToken,
      httpClient: httpClient,
    );
    final importer = LifeMateLegacyMutationImporter(
      outbox: outbox,
      apiBaseUri: apiBaseUri,
      legacyStorage: legacyStorage,
    );

    try {
      await importer.importPending(
        namespace: localNamespace,
        timeZone: normalizedTimeZone,
        legacyAccountIds: normalizedLegacyAccountIds,
      );

      return LifeMateSharedOfflineRuntime._(
        store: localStore,
        namespace: offlineNamespace,
        localNamespace: localNamespace,
        outbox: outbox,
        replayEngine: LifeMateLocalMutationReplayEngine(
          outbox: outbox,
          transport: transport,
          maximumMutationsPerRun: maximumMutationsPerRun,
          now: now,
        ),
        projectionReconciler: LifeMateLocalProjectionReconciler(
          store: localStore,
        ),
        transport: transport,
        legacyImporter: importer,
        timeZone: normalizedTimeZone,
        legacyAccountIds: normalizedLegacyAccountIds,
        ownsStore: ownsStore,
      );
    } catch (_) {
      transport.close();
      if (ownsStore) localStore.close();
      rethrow;
    }
  }

  Future<int> importLegacyPending() async {
    _requireOpen();
    return _legacyImporter.importPending(
      namespace: _localNamespace,
      timeZone: _timeZone,
      legacyAccountIds: _legacyAccountIds,
    );
  }

  Future<LifeMateOfflineSyncResult> flushDetailed() async {
    _requireOpen();
    await importLegacyPending();
    final result = await _replayEngine.replayEligible(namespace: _localNamespace);
    return LifeMateOfflineSyncResult(
      replayed: result.confirmed,
      conflicts: result.conflicts,
      terminalRejected: result.rejected,
      retainedForRetry: result.retainedForRetry,
      pendingRemaining: result.remaining,
    );
  }

  Future<LifeMateLocalSyncCheckpoint?> careEventCheckpoint() =>
      _checkpoint(LifeMateLocalProjectionDomain.careEvent);

  Future<LifeMateLocalSyncCheckpoint?> treatmentPlanCheckpoint() =>
      _checkpoint(LifeMateLocalProjectionDomain.treatmentPlan);

  Future<LifeMateLocalSyncCheckpoint?> treatmentOccurrenceCheckpoint() =>
      _checkpoint(LifeMateLocalProjectionDomain.treatmentOccurrence);

  Future<List<LifeMateLocalProjectionRecord>> careEventProjections() =>
      _projections(LifeMateLocalProjectionDomain.careEvent);

  Future<List<LifeMateLocalProjectionRecord>> treatmentPlanProjections() =>
      _projections(LifeMateLocalProjectionDomain.treatmentPlan);

  Future<List<LifeMateLocalProjectionRecord>> treatmentOccurrenceProjections() =>
      _projections(LifeMateLocalProjectionDomain.treatmentOccurrence);

  Future<LifeMateProjectionReconcileResult> applyCareEventPage({
    required LifeMateProjectionPullPage page,
    LifeMateBeforeProjectionCheckpoint? beforeCheckpoint,
  }) => _applyProjectionPage(
    domain: LifeMateLocalProjectionDomain.careEvent,
    page: page,
    beforeCheckpoint: beforeCheckpoint,
  );

  Future<LifeMateProjectionReconcileResult> applyTreatmentPlanPage({
    required LifeMateProjectionPullPage page,
    LifeMateBeforeProjectionCheckpoint? beforeCheckpoint,
  }) => _applyProjectionPage(
    domain: LifeMateLocalProjectionDomain.treatmentPlan,
    page: page,
    beforeCheckpoint: beforeCheckpoint,
  );

  Future<LifeMateProjectionReconcileResult> applyTreatmentOccurrencePage({
    required LifeMateProjectionPullPage page,
    LifeMateBeforeProjectionCheckpoint? beforeCheckpoint,
  }) => _applyProjectionPage(
    domain: LifeMateLocalProjectionDomain.treatmentOccurrence,
    page: page,
    beforeCheckpoint: beforeCheckpoint,
  );

  /// Persists one complete server-confirmed WellMate Home treatment window.
  /// The marker is written last, so a process death during cache refresh keeps
  /// the previous complete marker authoritative instead of exposing a partial
  /// replacement. Only opaque record IDs and bounded encrypted payloads are
  /// stored in the existing Account + Person + environment namespace.
  Future<void> cacheWellMateHomeSnapshot({
    required DateTime fromDate,
    required DateTime toDate,
    required Iterable<Map<String, dynamic>> treatmentPlans,
    required Iterable<Map<String, dynamic>> treatmentOccurrences,
  }) async {
    _requireOpen();
    final normalizedFrom = _dateOnly(fromDate);
    final normalizedTo = _dateOnly(toDate);
    if (normalizedTo.isBefore(normalizedFrom)) {
      throw ArgumentError.value(toDate, 'toDate');
    }

    final previousMarker = await _store.readProjection(
      namespace: _localNamespace,
      domain: LifeMateLocalProjectionDomain.syncMetadata,
      recordKey: _wellMateHomeMarkerKey,
    );
    final planKeys = await _cacheRecords(
      domain: LifeMateLocalProjectionDomain.treatmentPlan,
      values: treatmentPlans,
    );
    final occurrenceKeys = await _cacheRecords(
      domain: LifeMateLocalProjectionDomain.treatmentOccurrence,
      values: treatmentOccurrences,
    );

    await _store.putProjection(
      namespace: _localNamespace,
      domain: LifeMateLocalProjectionDomain.syncMetadata,
      recordKey: _wellMateHomeMarkerKey,
      payload: <String, dynamic>{
        'version': 1,
        'fromDate': _dateText(normalizedFrom),
        'toDate': _dateText(normalizedTo),
        'timeZone': _timeZone,
        'treatmentPlanKeys': planKeys,
        'treatmentOccurrenceKeys': occurrenceKeys,
      },
    );

    await _deleteStaleSnapshotRecords(
      previousMarker?.payload,
      field: 'treatmentPlanKeys',
      currentKeys: planKeys.toSet(),
      domain: LifeMateLocalProjectionDomain.treatmentPlan,
    );
    await _deleteStaleSnapshotRecords(
      previousMarker?.payload,
      field: 'treatmentOccurrenceKeys',
      currentKeys: occurrenceKeys.toSet(),
      domain: LifeMateLocalProjectionDomain.treatmentOccurrence,
    );
  }

  /// Returns a previously completed server-confirmed Home window. A caller can
  /// use this only after canonical runtime adoption; there is no account/person
  /// parameter that could widen the protected namespace. A non-overlapping
  /// date request deliberately returns null instead of fabricating fresh data.
  Future<Map<String, dynamic>?> readWellMateHomeSnapshot({
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    _requireOpen();
    final marker = await _store.readProjection(
      namespace: _localNamespace,
      domain: LifeMateLocalProjectionDomain.syncMetadata,
      recordKey: _wellMateHomeMarkerKey,
    );
    if (marker == null || marker.payload['version'] != 1) return null;

    final cachedFrom = DateTime.tryParse(
      marker.payload['fromDate']?.toString() ?? '',
    );
    final cachedTo = DateTime.tryParse(
      marker.payload['toDate']?.toString() ?? '',
    );
    if (cachedFrom == null || cachedTo == null) return null;
    final requestedFrom = _dateOnly(fromDate);
    final requestedTo = _dateOnly(toDate);
    if (requestedTo.isBefore(cachedFrom) || requestedFrom.isAfter(cachedTo)) {
      return null;
    }

    final plans = await _readSnapshotRecords(
      marker.payload,
      field: 'treatmentPlanKeys',
      domain: LifeMateLocalProjectionDomain.treatmentPlan,
    );
    final occurrences = await _readSnapshotRecords(
      marker.payload,
      field: 'treatmentOccurrenceKeys',
      domain: LifeMateLocalProjectionDomain.treatmentOccurrence,
    );
    if (plans == null || occurrences == null) return null;

    final careEvents = await careEventProjections();
    return <String, dynamic>{
      'currentUser': <String, dynamic>{
        'profile': <String, dynamic>{'timeZone': _timeZone},
      },
      'treatmentPlans': plans,
      'doseOccurrences': occurrences
          .where((value) => _payloadDateInRange(
                value,
                field: 'scheduledLocalDate',
                fromDate: requestedFrom,
                toDate: requestedTo,
              ))
          .toList(growable: false),
      'careEvents': careEvents
          .map((record) => record.payload)
          .where((value) => _payloadDateInRange(
                value,
                field: 'scheduledLocalDate',
                fromDate: requestedFrom,
                toDate: requestedTo,
              ))
          .toList(growable: false),
      'offlineCached': true,
      'offlineCachedAtUtc': marker.storedAtUtc.toIso8601String(),
    };
  }

  Future<int> pendingMutationCount() async {
    _requireOpen();
    await importLegacyPending();
    final mutations = await _outbox.list(namespace: _localNamespace);
    return mutations.where(_isPendingForReplay).length;
  }

  /// Accepts one already-local-validated treatment edit into the same protected
  /// Account + Person + environment outbox used by adherence. This method does
  /// not infer medication timing or bypass the canonical expected-revision
  /// conflict contract; it only binds the validated mutation to this runtime's
  /// already-adopted namespace. The protected outbox record stays internal;
  /// callers receive acknowledgement only.
  Future<void> enqueueTreatmentEdit({
    required String mutationId,
    required String treatmentPlanId,
    required int version,
    required int medicationVersion,
    required String medicationName,
    String? strengthText,
    String? form,
    required String doseText,
    String? instructions,
    required DateTime startDate,
    DateTime? endDate,
    required String timeZone,
    required List<Map<String, String>> schedules,
    required int patientReminderMinutesBefore,
    required int caregiverReminderMinutesBefore,
    required String status,
    DateTime? createdAtUtc,
  }) async {
    _requireOpen();
    await LifeMateOfflineTreatmentMutation.enqueueEdit(
      outbox: _outbox,
      namespace: _localNamespace,
      mutationId: mutationId,
      treatmentPlanId: treatmentPlanId,
      version: version,
      medicationVersion: medicationVersion,
      medicationName: medicationName,
      strengthText: strengthText,
      form: form,
      doseText: doseText,
      instructions: instructions,
      startDate: startDate,
      endDate: endDate,
      timeZone: timeZone,
      schedules: schedules,
      patientReminderMinutesBefore: patientReminderMinutesBefore,
      caregiverReminderMinutesBefore: caregiverReminderMinutesBefore,
      status: status,
      createdAtUtc: createdAtUtc,
    );
  }

  Future<Map<String, String>> pendingAdherenceStates() async {
    _requireOpen();
    await importLegacyPending();
    final mutations = await _outbox.list(namespace: _localNamespace);
    final result = <String, String>{};
    for (final mutation in mutations) {
      if (mutation.domain != LifeMateMutationDomain.adherence ||
          !_isPendingForReplay(mutation)) {
        continue;
      }
      final status = mutation.payload['status']?.toString().toLowerCase();
      if (status != 'taken' && status != 'skipped') continue;
      result[mutation.sourceKey] = status!;
    }
    return result;
  }

  Future<void> purgeCurrentAccount({
    required bool discardPendingAndCachedData,
  }) async {
    _requireOpen();
    if (!discardPendingAndCachedData) {
      throw const LifeMateLocalDataPurgeConfirmationRequiredException();
    }
    await _store.purgeAccount(
      environmentId: _namespace.environmentId,
      accountId: _namespace.accountId,
    );
    _accountPurged = true;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _transport.close();
    if (_ownsStore) _store.close();
  }

  Future<List<String>> _cacheRecords({
    required LifeMateLocalProjectionDomain domain,
    required Iterable<Map<String, dynamic>> values,
  }) async {
    final keys = <String>[];
    for (final value in values) {
      final key = value['id']?.toString().trim() ?? '';
      if (key.isEmpty) {
        throw const FormatException(
          'Server-confirmed offline projection is missing an id.',
        );
      }
      await _store.putProjection(
        namespace: _localNamespace,
        domain: domain,
        recordKey: key,
        payload: value,
        sourceRevision: _optionalText(value['version']),
        sourceUpdatedAtUtc: _optionalUtc(value['updatedAtUtc']),
      );
      keys.add(key);
    }
    return List<String>.unmodifiable(keys);
  }

  Future<List<Map<String, dynamic>>?> _readSnapshotRecords(
    Map<String, dynamic> marker, {
    required String field,
    required LifeMateLocalProjectionDomain domain,
  }) async {
    final rawKeys = marker[field];
    if (rawKeys is! List) return null;
    final values = <Map<String, dynamic>>[];
    for (final rawKey in rawKeys) {
      final key = rawKey?.toString().trim() ?? '';
      if (key.isEmpty) return null;
      final record = await _store.readProjection(
        namespace: _localNamespace,
        domain: domain,
        recordKey: key,
      );
      if (record == null) return null;
      values.add(record.payload);
    }
    return values;
  }

  Future<void> _deleteStaleSnapshotRecords(
    Map<String, dynamic>? previousMarker, {
    required String field,
    required Set<String> currentKeys,
    required LifeMateLocalProjectionDomain domain,
  }) async {
    final previous = previousMarker?[field];
    if (previous is! List) return;
    for (final rawKey in previous) {
      final key = rawKey?.toString().trim() ?? '';
      if (key.isEmpty || currentKeys.contains(key)) continue;
      await _store.deleteProjection(
        namespace: _localNamespace,
        domain: domain,
        recordKey: key,
      );
    }
  }

  Future<LifeMateLocalSyncCheckpoint?> _checkpoint(
    LifeMateLocalProjectionDomain domain,
  ) {
    _requireOpen();
    return _projectionReconciler.checkpoint(
      namespace: _localNamespace,
      domain: domain,
    );
  }

  Future<List<LifeMateLocalProjectionRecord>> _projections(
    LifeMateLocalProjectionDomain domain,
  ) {
    _requireOpen();
    return _store.listDomain(namespace: _localNamespace, domain: domain);
  }

  Future<LifeMateProjectionReconcileResult> _applyProjectionPage({
    required LifeMateLocalProjectionDomain domain,
    required LifeMateProjectionPullPage page,
    LifeMateBeforeProjectionCheckpoint? beforeCheckpoint,
  }) {
    _requireOpen();
    return _projectionReconciler.applyPage(
      namespace: _localNamespace,
      domain: domain,
      page: page,
      beforeCheckpoint: beforeCheckpoint,
    );
  }

  void _requireOpen() {
    if (_closed) throw StateError('LifeMate shared offline runtime is closed.');
    if (_accountPurged) {
      throw StateError('LifeMate shared offline runtime account was purged.');
    }
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);

  static String _dateText(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static String? _optionalText(Object? value) {
    final normalized = value?.toString().trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  static DateTime? _optionalUtc(Object? value) {
    final text = _optionalText(value);
    if (text == null) return null;
    return DateTime.tryParse(text)?.toUtc();
  }

  static bool _payloadDateInRange(
    Map<String, dynamic> payload, {
    required String field,
    required DateTime fromDate,
    required DateTime toDate,
  }) {
    final parsed = DateTime.tryParse(payload[field]?.toString() ?? '');
    if (parsed == null) return false;
    final day = _dateOnly(parsed);
    return !day.isBefore(fromDate) && !day.isAfter(toDate);
  }

  static bool _isPendingForReplay(LifeMateDurableMutation mutation) =>
      mutation.state == LifeMateMutationSyncState.pending ||
      mutation.state == LifeMateMutationSyncState.retryScheduled;
}
