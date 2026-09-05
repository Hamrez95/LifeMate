import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:lifemate_core/lifemate_core.dart';

import 'care_event_projection_sync.dart';
import 'durable_http_client.dart';
import 'incremental_projection_api.dart';
import 'lifemate_api_client.dart';
import 'offline_mutation_queue.dart';
import 'offline_sync_result.dart';
import 'shared_offline_runtime.dart';

class LifeMatePendingSyncEvent {
  const LifeMatePendingSyncEvent({
    required this.occurrenceId,
    required this.status,
  });

  final String occurrenceId;
  final String status;
}

final ValueNotifier<LifeMatePendingSyncEvent?> lifeMatePendingSyncEvent =
    ValueNotifier<LifeMatePendingSyncEvent?>(null);

/// Low-cardinality offline recovery feedback for UI notices. This intentionally
/// contains no account/person/occurrence IDs, health values or server messages.
final ValueNotifier<LifeMateOfflineSyncResult?> lifeMateOfflineSyncResult =
    ValueNotifier<LifeMateOfflineSyncResult?>(null);

class DurableLifeMateApiClient extends LifeMateApiClient {
  DurableLifeMateApiClient._({
    required Uri baseUri,
    required AccessTokenProvider accessToken,
    required LifeMateAccountIdProvider accountId,
    required LifeMateDurableHttpClient durableHttp,
    required LifeMateIncrementalProjectionApi incrementalProjectionApi,
  }) : _baseUri = baseUri,
       _accessToken = accessToken,
       _legacyAuthenticatedAccountId = accountId,
       _durableHttp = durableHttp,
       _incrementalProjectionApi = incrementalProjectionApi,
       super(
         baseUri: baseUri,
         accessToken: accessToken,
         httpClient: durableHttp,
       );

  factory DurableLifeMateApiClient({
    required Uri baseUri,
    required AccessTokenProvider accessToken,
    required LifeMateAccountIdProvider accountId,
    LifeMateOfflineMutationQueue? queue,
    http.Client? innerHttpClient,
  }) {
    final durableHttp = LifeMateDurableHttpClient(
      apiBaseUri: baseUri,
      accessToken: accessToken,
      accountId: accountId,
      queue: queue,
      inner: innerHttpClient,
    );
    final incrementalProjectionApi = LifeMateIncrementalProjectionApi(
      baseUri: baseUri,
      accessToken: accessToken,
    );
    return DurableLifeMateApiClient._(
      baseUri: baseUri,
      accessToken: accessToken,
      accountId: accountId,
      durableHttp: durableHttp,
      incrementalProjectionApi: incrementalProjectionApi,
    );
  }

  final Uri _baseUri;
  final AccessTokenProvider _accessToken;
  final LifeMateAccountIdProvider _legacyAuthenticatedAccountId;
  final LifeMateDurableHttpClient _durableHttp;
  final LifeMateIncrementalProjectionApi _incrementalProjectionApi;
  LifeMateSharedOfflineRuntime? _sharedRuntime;
  LifeMateCareEventProjectionSync? _careEventProjectionSync;
  String? _sharedRuntimeLegacyAccountId;

  @override
  Future<Map<String, dynamic>> bootstrapUser({
    required String? displayName,
    required String? email,
    String locale = 'fa',
    String timeZone = 'Asia/Tehran',
  }) async {
    // Native app bootstrap is the transition point from the historical
    // auth-subject queue to canonical Account + Person scope. Web deliberately
    // keeps the existing browser-compatible replay path until a separately
    // reviewed protected browser store exists.
    if (!kIsWeb) {
      _durableHttp.deferReplayUntilDelegate();
    }
    final bootstrapped = await super.bootstrapUser(
      displayName: displayName,
      email: email,
      locale: locale,
      timeZone: timeZone,
    );
    if (kIsWeb) return bootstrapped;

    final legacyAuthenticatedAccountId = _legacyAuthenticatedAccountId()
        ?.trim();
    if (legacyAuthenticatedAccountId == null ||
        legacyAuthenticatedAccountId.isEmpty) {
      throw const LifeMateApiException(
        statusCode: 401,
        code: 'offline_identity_unavailable',
        message: 'Authenticated identity is unavailable for offline runtime.',
      );
    }

    final capabilities = await super.getCapabilities();
    final personId = capabilities.selfPersonId?.trim();
    if (personId == null || personId.isEmpty) {
      throw const LifeMateApiException(
        statusCode: 409,
        code: 'identity_person_mapping_missing',
        message: 'The LifeMate person mapping is unavailable.',
      );
    }
    await adoptSharedOfflineRuntime(
      environmentId: _baseUri.toString(),
      accountId: capabilities.accountId,
      personId: personId,
      legacyAuthenticatedAccountId: legacyAuthenticatedAccountId,
      timeZone: timeZone,
    );
    return bootstrapped;
  }

  /// Moves replay ownership from the pre-#831 auth-subject queue to the shared
  /// encrypted Environment + canonical Account + Person runtime. The caller
  /// must supply canonical IDs from lifemate-api capabilities and the current
  /// authenticated legacy ID separately; UUID equality is never assumed.
  Future<void> adoptSharedOfflineRuntime({
    required String environmentId,
    required String accountId,
    required String personId,
    required String legacyAuthenticatedAccountId,
    required String timeZone,
    LifeMateLocalHealthStore? localStore,
    LifeMateMutationStorage? legacyStorage,
  }) async {
    final normalizedAccount = accountId.trim();
    final normalizedPerson = personId.trim();
    final normalizedEnvironment = environmentId.trim();
    final normalizedLegacyAccount = legacyAuthenticatedAccountId.trim();
    final normalizedTimeZone = timeZone.trim();
    if (normalizedAccount.isEmpty ||
        normalizedPerson.isEmpty ||
        normalizedEnvironment.isEmpty ||
        normalizedLegacyAccount.isEmpty ||
        normalizedTimeZone.isEmpty) {
      throw ArgumentError(
        'Shared offline runtime requires environment, canonical account, Person, authenticated legacy account and timezone.',
      );
    }
    if (_legacyAuthenticatedAccountId()?.trim() != normalizedLegacyAccount) {
      throw StateError(
        'Authenticated account changed during offline adoption.',
      );
    }

    final namespace = LifeMateOfflineNamespace(
      environmentId: normalizedEnvironment,
      accountId: normalizedAccount,
      personId: normalizedPerson,
    );
    final current = _activeSharedRuntime();
    if (current != null && _sameNamespace(current.namespace, namespace)) return;

    final next = await LifeMateSharedOfflineRuntime.open(
      namespace: namespace,
      timeZone: normalizedTimeZone,
      apiBaseUri: _baseUri,
      accessToken: _accessToken,
      legacyAccountIds: <String>{normalizedLegacyAccount},
      store: localStore,
      legacyStorage: legacyStorage ?? _durableHttp.migrationStorage,
    );
    if (_legacyAuthenticatedAccountId()?.trim() != normalizedLegacyAccount) {
      next.close();
      throw StateError(
        'Authenticated account changed during offline adoption.',
      );
    }

    final previous = _sharedRuntime;
    _sharedRuntime = next;
    _careEventProjectionSync = LifeMateCareEventProjectionSync(
      runtime: next,
      api: _incrementalProjectionApi,
    );
    _sharedRuntimeLegacyAccountId = normalizedLegacyAccount;
    _durableHttp.useReplayDelegate(() async {
      if (_legacyAuthenticatedAccountId()?.trim() != normalizedLegacyAccount) {
        return const LifeMateOfflineSyncResult();
      }
      return next.flushDetailed();
    });
    previous?.close();
  }

  @override
  Future<Map<String, dynamic>> reportDose({
    required String occurrenceId,
    required String clientRequestId,
    required int version,
    required String status,
    required DateTime occurredAtUtc,
  }) async {
    try {
      return await super.reportDose(
        occurrenceId: occurrenceId,
        clientRequestId: clientRequestId,
        version: version,
        status: status,
        occurredAtUtc: occurredAtUtc,
      );
    } on LifeMateOfflineQueuedException {
      lifeMatePendingSyncEvent.value = LifeMatePendingSyncEvent(
        occurrenceId: occurrenceId,
        status: status,
      );
      return <String, dynamic>{
        'id': occurrenceId,
        'status': 'pending_sync',
        'pendingStatus': status,
        'version': version,
        'pendingSync': true,
        'clientRequestId': clientRequestId,
      };
    }
  }

  @override
  Future<Map<String, dynamic>> getHomeSnapshot({
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    final pendingBeforeRead = await _pendingDoseStates();
    try {
      final snapshot = await super.getHomeSnapshot(
        fromDate: fromDate,
        toDate: toDate,
      );
      await _cacheServerHomeSnapshot(
        snapshot,
        fromDate: fromDate,
        toDate: toDate,
      );
      _overlaySnapshotOccurrences(snapshot, pendingBeforeRead);
      return snapshot;
    } on LifeMateApiException catch (error) {
      if (!_canUseOwnerCacheFor(error)) rethrow;
      final runtime = _activeSharedRuntime();
      if (runtime == null) rethrow;
      Map<String, dynamic>? cached;
      try {
        cached = await runtime.readWellMateHomeSnapshot(
          fromDate: fromDate,
          toDate: toDate,
        );
      } catch (_) {
        throw error;
      }
      if (cached == null) throw error;
      _overlaySnapshotOccurrences(cached, pendingBeforeRead);
      return cached;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getDoseOccurrences({
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    final pendingBeforeRead = await _pendingDoseStates();
    try {
      final values = await super.getDoseOccurrences(
        fromDate: fromDate,
        toDate: toDate,
      );
      if (pendingBeforeRead.isEmpty) return values;
      return _overlayOccurrences(values, pendingBeforeRead);
    } on LifeMateApiException catch (error) {
      if (!_canUseOwnerCacheFor(error)) rethrow;
      final runtime = _activeSharedRuntime();
      if (runtime == null) rethrow;
      Map<String, dynamic>? cached;
      try {
        cached = await runtime.readWellMateHomeSnapshot(
          fromDate: fromDate,
          toDate: toDate,
        );
      } catch (_) {
        throw error;
      }
      final raw = cached?['doseOccurrences'];
      if (raw is! List) throw error;
      return _overlayOccurrences(raw, pendingBeforeRead);
    }
  }

  Future<void> _cacheServerHomeSnapshot(
    Map<String, dynamic> snapshot, {
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    final runtime = _activeSharedRuntime();
    if (runtime == null) return;
    final plans = _mapList(snapshot['treatmentPlans']);
    final occurrences = _mapList(snapshot['doseOccurrences']);
    if (plans == null || occurrences == null) return;
    try {
      await runtime.cacheWellMateHomeSnapshot(
        fromDate: fromDate,
        toDate: toDate,
        treatmentPlans: plans,
        treatmentOccurrences: occurrences,
      );
    } catch (_) {
      // Online server truth remains usable when local protected cache refresh
      // fails. No payload or exception text is logged from this PHI boundary.
    }
  }

  void _overlaySnapshotOccurrences(
    Map<String, dynamic> snapshot,
    Map<String, String> pending,
  ) {
    if (pending.isEmpty) return;
    final occurrences = snapshot['doseOccurrences'];
    if (occurrences is List) {
      snapshot['doseOccurrences'] = _overlayOccurrences(occurrences, pending);
    }
  }

  Future<Map<String, String>> _pendingDoseStates() async {
    final shared = _activeSharedRuntime();
    if (shared != null) return shared.pendingAdherenceStates();

    final pending = await _durableHttp.pendingMutations();
    final result = <String, String>{};
    for (final mutation in pending) {
      final uri = Uri.tryParse(mutation.uri);
      if (uri == null || uri.pathSegments.length < 2) continue;
      final reportIndex = uri.pathSegments.lastIndexOf('report');
      if (reportIndex <= 0) continue;
      final occurrenceId = uri.pathSegments[reportIndex - 1];
      dynamic body;
      try {
        body = jsonDecode(mutation.body);
      } catch (_) {
        continue;
      }
      if (body is! Map) continue;
      final status = body['status']?.toString().toLowerCase();
      if (status != 'taken' && status != 'skipped') continue;
      result[occurrenceId] = status!;
    }
    return result;
  }

  List<Map<String, dynamic>> _overlayOccurrences(
    List<dynamic> values,
    Map<String, String> pending,
  ) {
    return values
        .whereType<Map>()
        .map((raw) {
          final value = <String, dynamic>{
            for (final entry in raw.entries) entry.key.toString(): entry.value,
          };
          final id = value['id']?.toString();
          final desiredStatus = id == null ? null : pending[id];
          if (desiredStatus == null) return value;

          final serverStatus = value['status']?.toString().toLowerCase();
          if (serverStatus == 'taken' || serverStatus == 'skipped') {
            return value;
          }
          return <String, dynamic>{
            ...value,
            'status': 'pending_sync',
            'pendingSync': true,
            'pendingStatus': desiredStatus,
          };
        })
        .toList(growable: false);
  }

  /// Accepts a complete locally validated treatment edit into the same
  /// encrypted Account + Person namespace already adopted by this client.
  /// A short-lived handle to the canonical local store is used only to enqueue
  /// the durable envelope; no second queue/database model is introduced.
  Future<LifeMateDurableMutation> enqueueTreatmentPlanEdit({
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
    String? mutationId,
    @visibleForTesting LifeMateLocalHealthStore? localStore,
  }) async {
    final runtime = _activeSharedRuntime();
    if (runtime == null) {
      throw StateError(
        'Canonical shared offline runtime must be adopted before treatment enqueue.',
      );
    }
    final ownsStore = localStore == null;
    final store = localStore ?? await LifeMateLocalHealthStore.openDefault();
    try {
      final outbox = LifeMateLocalMutationOutbox(store: store);
      return LifeMateOfflineTreatmentMutation.enqueueEdit(
        outbox: outbox,
        namespace: runtime.namespace.toLocalNamespace(),
        mutationId: mutationId?.trim().isNotEmpty == true
            ? mutationId!.trim()
            : LifeMateApiClient.createClientRequestId(),
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
      );
    } finally {
      if (ownsStore) store.close();
    }
  }

  Future<int> flushPendingMutations() async =>
      (await flushPendingMutationsDetailed()).synced;

  Future<LifeMateOfflineSyncResult> flushPendingMutationsDetailed() async {
    final result = await _durableHttp.flushPendingDetailed();
    lifeMateOfflineSyncResult.value = result;
    return result;
  }

  /// Pulls canonical owner care-event projections into the already-adopted
  /// protected Account + Person runtime. The callback is the required hook for
  /// affected #830 reminder regeneration and runs before cursor acknowledgement.
  /// Callers should use this on reconnect/app-resume only after bootstrap has
  /// resolved canonical identity. No parallel database or scheduler is created.
  Future<LifeMateCareEventProjectionSyncResult> syncCareEventProjections({
    int pageSize = 100,
    int maximumPages = 10,
    LifeMateBeforeProjectionCheckpoint? beforeCheckpoint,
  }) async {
    final runtime = _activeSharedRuntime();
    final sync = _careEventProjectionSync;
    if (runtime == null || sync == null) {
      throw StateError(
        'Canonical shared offline runtime must be adopted before projection sync.',
      );
    }
    return sync.sync(
      pageSize: pageSize,
      maximumPages: maximumPages,
      beforeCheckpoint: beforeCheckpoint,
    );
  }

  Future<int> pendingMutationCount() async {
    final shared = _activeSharedRuntime();
    return shared == null
        ? _durableHttp.pendingCount()
        : shared.pendingMutationCount();
  }

  LifeMateSharedOfflineRuntime? _activeSharedRuntime() {
    final runtime = _sharedRuntime;
    final boundLegacyAccount = _sharedRuntimeLegacyAccountId;
    if (runtime == null ||
        boundLegacyAccount == null ||
        _legacyAuthenticatedAccountId()?.trim() != boundLegacyAccount) {
      return null;
    }
    return runtime;
  }

  @override
  void close() {
    _careEventProjectionSync = null;
    _sharedRuntime?.close();
    _sharedRuntime = null;
    _sharedRuntimeLegacyAccountId = null;
    _incrementalProjectionApi.close();
    super.close();
  }

  static List<Map<String, dynamic>>? _mapList(Object? value) {
    if (value is! List) return null;
    final result = <Map<String, dynamic>>[];
    for (final item in value) {
      if (item is! Map) return null;
      result.add(<String, dynamic>{
        for (final entry in item.entries) entry.key.toString(): entry.value,
      });
    }
    return result;
  }

  static bool _canUseOwnerCacheFor(LifeMateApiException error) =>
      error.statusCode == 0 ||
      error.statusCode == 408 ||
      error.statusCode == 429 ||
      error.statusCode == 500 ||
      error.statusCode == 502 ||
      error.statusCode == 503 ||
      error.statusCode == 504;

  static bool _sameNamespace(
    LifeMateOfflineNamespace left,
    LifeMateOfflineNamespace right,
  ) =>
      left.environmentId == right.environmentId &&
      left.accountId == right.accountId &&
      left.personId == right.personId;
}