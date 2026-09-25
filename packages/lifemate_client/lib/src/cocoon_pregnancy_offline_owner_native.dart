import 'package:lifemate_core/lifemate_core.dart';

import 'capabilities.dart';
import 'cocoon_pregnancy.dart';
import 'cocoon_pregnancy_daily_api.dart'
    show CocoonApprovedSymptomCatalog, CocoonPregnancySymptomCatalogEntry;
import 'cocoon_pregnancy_offline_content_native.dart';
import 'cocoon_pregnancy_offline_snapshot_native.dart';
import 'lifemate_api_client.dart' show AccessTokenProvider;
import 'offline_identity_adoption_native.dart';
import 'offline_mutation_queue.dart' show LifeMateMutationStorage;
import 'offline_sync_result.dart';
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

  /// Accepts an owner-entered pregnancy check-in into the canonical protected
  /// Account + Person outbox. The returned acknowledgement is local-only; UI
  /// must keep it pending until a later authoritative server refresh confirms it.
  Future<void> enqueueDailyCheckIn({
    required String clientRequestId,
    required DateTime observedAtUtc,
    required DateTime localDate,
    required String feeling,
    required String energy,
    DateTime? createdAtUtc,
  }) => _withOutbox<void>((outbox, namespace) async {
    await LifeMateOfflinePregnancyDailyMutation.enqueueCheckIn(
      outbox: outbox,
      namespace: namespace,
      mutationId: clientRequestId,
      observedAtUtc: observedAtUtc,
      localDate: localDate,
      timeZone: timeZone,
      feeling: feeling,
      energy: energy,
      createdAtUtc: createdAtUtc,
    );
  });

  Future<void> enqueueSymptom({
    required String clientRequestId,
    required DateTime observedAtUtc,
    required DateTime localDate,
    required String symptomCode,
    required String intensity,
    required CocoonApprovedSymptomCatalog approvedCatalog,
    String? note,
    DateTime? createdAtUtc,
  }) => _withOutbox<void>((outbox, namespace) async {
    if (!approvedCatalog.allows(symptomCode)) {
      throw ArgumentError.value(
        symptomCode,
        'symptomCode',
        'is not present in the approved symptom catalog.',
      );
    }
    await LifeMateOfflinePregnancyDailyMutation.enqueueSymptom(
      outbox: outbox,
      namespace: namespace,
      mutationId: clientRequestId,
      observedAtUtc: observedAtUtc,
      localDate: localDate,
      timeZone: timeZone,
      catalogVersion: approvedCatalog.version,
      symptomCode: symptomCode,
      intensity: intensity,
      note: note,
      createdAtUtc: createdAtUtc,
    );
  });

  Future<void> enqueueMood({
    required String clientRequestId,
    required DateTime observedAtUtc,
    required DateTime localDate,
    required String moodCode,
    DateTime? createdAtUtc,
  }) => _withOutbox<void>((outbox, namespace) async {
    await LifeMateOfflinePregnancyDailyMutation.enqueueMood(
      outbox: outbox,
      namespace: namespace,
      mutationId: clientRequestId,
      observedAtUtc: observedAtUtc,
      localDate: localDate,
      timeZone: timeZone,
      moodCode: moodCode,
      createdAtUtc: createdAtUtc,
    );
  });

  /// Persists a server-authored, reviewed symptom catalog in the protected
  /// Account + Person namespace. It is a display/validation snapshot only;
  /// the server still verifies the catalog version and symptom code.
  Future<void> cacheApprovedSymptomCatalog({
    required String locale,
    required CocoonApprovedSymptomCatalog catalog,
  }) async {
    final normalizedLocale = _catalogLocale(locale);
    final adoption = await _requireAdoption();
    await _withContentCache<void>(
      adoption,
      (cache) => cache.writeApprovedContent(
        recordKey: 'symptom-catalog:$normalizedLocale',
        contentVersion: catalog.version,
        payload: <String, dynamic>{
          'locale': normalizedLocale,
          'entries': catalog.entries
              .map(
                (entry) => <String, dynamic>{
                  'code': entry.code,
                  'label': entry.label,
                  'sortOrder': entry.sortOrder,
                },
              )
              .toList(growable: false),
        },
      ),
    );
  }

  /// Returns only a catalog previously written through
  /// [cacheApprovedSymptomCatalog] for this adopted owner namespace.
  Future<CocoonApprovedSymptomCatalog?> readCachedApprovedSymptomCatalog({
    required String locale,
  }) async {
    final normalizedLocale = _catalogLocale(locale);
    final adoption = await _identityStore.lookup(
      environmentId: _environmentId,
      legacyAccountId: legacyAccountId,
    );
    if (adoption == null) return null;
    final record =
        await _withContentCache<CocoonPregnancyOfflineContentRecord?>(
          adoption,
          (cache) => cache.readApprovedContent(
            recordKey: 'symptom-catalog:$normalizedLocale',
          ),
        );
    if (record == null || record.payload['locale'] != normalizedLocale) {
      return null;
    }
    final rawEntries = record.payload['entries'];
    if (rawEntries is! List) return null;
    try {
      final entries = rawEntries
          .whereType<Map>()
          .map(
            (entry) => CocoonPregnancySymptomCatalogEntry.fromJson(
              Map<String, dynamic>.from(entry),
            ),
          )
          .toList(growable: false);
      return CocoonApprovedSymptomCatalog(
        version: record.contentVersion,
        codes: entries.map((entry) => entry.code),
        entries: entries,
      );
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  Future<void> enqueueMeasurement({
    required String clientRequestId,
    required String observationType,
    required double valuePrimary,
    double? valueSecondary,
    String? note,
    required DateTime observedAtUtc,
    required DateTime observedLocalDate,
    DateTime? createdAtUtc,
  }) => _withOutbox<void>((outbox, namespace) async {
    await LifeMateOfflinePregnancyMeasurementMutation.enqueueCreate(
      outbox: outbox,
      namespace: namespace,
      mutationId: clientRequestId,
      observationType: observationType,
      valuePrimary: valuePrimary,
      valueSecondary: valueSecondary,
      note: note,
      observedAtUtc: observedAtUtc,
      observedLocalDate: observedLocalDate,
      timeZone: timeZone,
      createdAtUtc: createdAtUtc,
    );
  });

  /// Queues the same canonical care-event payload used by the online pregnancy
  /// Calendar endpoint. Presentation date/time labels are deliberately not
  /// accepted here; callers must supply typed canonical date/time values.
  Future<void> enqueueCalendarEvent({
    required String clientRequestId,
    required String classification,
    required String eventType,
    required String title,
    String? providerName,
    String? specialty,
    String? medicationName,
    String? doseText,
    String? administrationRoute,
    String? reason,
    String? instructions,
    String? centerName,
    String? addressLine,
    String? phoneNumber,
    required DateTime scheduledLocalDate,
    required String scheduledLocalTime,
    required int patientReminderMinutesBefore,
    required int caregiverReminderMinutesBefore,
    DateTime? createdAtUtc,
  }) => _withOutbox<void>((outbox, namespace) async {
    await LifeMateOfflinePregnancyCalendarMutation.enqueueCreate(
      outbox: outbox,
      namespace: namespace,
      mutationId: clientRequestId,
      classification: classification,
      eventType: eventType,
      title: title,
      providerName: providerName,
      specialty: specialty,
      medicationName: medicationName,
      doseText: doseText,
      administrationRoute: administrationRoute,
      reason: reason,
      instructions: instructions,
      centerName: centerName,
      addressLine: addressLine,
      phoneNumber: phoneNumber,
      scheduledLocalDate: scheduledLocalDate,
      scheduledLocalTime: scheduledLocalTime,
      timeZone: timeZone,
      patientReminderMinutesBefore: patientReminderMinutesBefore,
      caregiverReminderMinutesBefore: caregiverReminderMinutesBefore,
      createdAtUtc: createdAtUtc,
    );
  });

  /// Privacy-minimal pending projection for Cocoon UI. Only mutation IDs are
  /// returned; no symptom, mood, measurement, appointment or note payload is
  /// exposed by this status query.
  Future<Set<String>> pendingPregnancyMutationIds() =>
      _withOutbox<Set<String>>((outbox, namespace) async {
        final values = await outbox.list(namespace: namespace);
        return values
            .where(
              (value) =>
                  value.state == LifeMateMutationSyncState.pending ||
                  value.state == LifeMateMutationSyncState.retryScheduled,
            )
            .where(
              (value) =>
                  value.sourceKey.startsWith('pregnancy-check-in:') ||
                  value.sourceKey.startsWith('pregnancy-symptom:') ||
                  value.sourceKey.startsWith('pregnancy-mood:') ||
                  value.sourceKey.startsWith('pregnancy-care-event-create:') ||
                  value.sourceKey.startsWith('pending-pregnancy-measurement:'),
            )
            .map((value) => value.mutationId)
            .toSet();
      });

  /// Replays through the one shared runtime. A successful replay removes the
  /// local outbox item, but UI still refreshes the authoritative Cocoon source
  /// before presenting it as server-confirmed.
  Future<LifeMateOfflineSyncResult> flushPending() async {
    final adoption = await _requireAdoption();
    final ownsStore = _localStore == null;
    final store = _localStore ?? await LifeMateLocalHealthStore.openDefault();
    LifeMateSharedOfflineRuntime? runtime;
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
      return await runtime.flushDetailed();
    } finally {
      runtime?.close();
      if (ownsStore) store.close();
    }
  }

  Future<void> forgetAdoptedOwner() => _identityStore.forget(
    environmentId: _environmentId,
    legacyAccountId: legacyAccountId,
  );

  Future<T> _withOutbox<T>(
    Future<T> Function(
      LifeMateLocalMutationOutbox outbox,
      LifeMateLocalNamespace namespace,
    )
    action,
  ) async {
    final adoption = await _requireAdoption();
    final ownsStore = _localStore == null;
    final store = _localStore ?? await LifeMateLocalHealthStore.openDefault();
    try {
      final outbox = LifeMateLocalMutationOutbox(store: store);
      return await action(outbox, adoption.toLocalNamespace());
    } finally {
      if (ownsStore) store.close();
    }
  }

  Future<LifeMateOfflineIdentityAdoption> _requireAdoption() async {
    final adoption = await _identityStore.lookup(
      environmentId: _environmentId,
      legacyAccountId: legacyAccountId,
    );
    if (adoption == null) {
      throw StateError(
        'Cocoon offline mutations require a previously adopted canonical owner.',
      );
    }
    return adoption;
  }

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

  Future<T> _withContentCache<T>(
    LifeMateOfflineIdentityAdoption adoption,
    Future<T> Function(CocoonPregnancyOfflineContentCache cache) action,
  ) async {
    final ownsStore = _localStore == null;
    final store = _localStore ?? await LifeMateLocalHealthStore.openDefault();
    LifeMateSharedOfflineRuntime? runtime;
    CocoonPregnancyOfflineContentCache? cache;
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
      cache = await CocoonPregnancyOfflineContentCache.open(
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

  static String _catalogLocale(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized != 'en' && normalized != 'fa') {
      throw ArgumentError.value(value, 'locale', 'must be en or fa.');
    }
    return normalized;
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
