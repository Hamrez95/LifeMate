import 'package:http/http.dart' as http;
import 'package:lifemate_core/lifemate_core.dart';

import 'lifemate_api_client.dart' show AccessTokenProvider;
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

  static String _required(String value, String field) {
    final normalized = value.trim();
    if (normalized.isEmpty) throw ArgumentError.value(value, field);
    return normalized;
  }
}

/// Web builds intentionally do not instantiate the native encrypted SQLite
/// execution engine. Remote API behavior remains available, while offline
/// health replay/projection persistence fails closed instead of falling back to
/// an unprotected browser store.
final class LifeMateSharedOfflineRuntime {
  LifeMateSharedOfflineRuntime._(this.namespace);

  final LifeMateOfflineNamespace namespace;

  static Future<LifeMateSharedOfflineRuntime> open({
    required Object namespace,
    required String timeZone,
    required Uri apiBaseUri,
    required AccessTokenProvider accessToken,
    Set<String> legacyAccountIds = const <String>{},
    Object? store,
    LifeMateMutationStorage? legacyStorage,
    http.Client? httpClient,
    int maximumMutationsPerRun = 25,
    DateTime Function()? now,
  }) async {
    throw UnsupportedError(
      'Protected offline health execution is unavailable on web.',
    );
  }

  Future<int> importLegacyPending() => Future<int>.value(0);

  Future<LifeMateOfflineSyncResult> flushDetailed() =>
      Future<LifeMateOfflineSyncResult>.value(
        const LifeMateOfflineSyncResult(),
      );

  Future<LifeMateLocalSyncCheckpoint?> careEventCheckpoint() =>
      _unsupportedCheckpoint();

  Future<LifeMateLocalSyncCheckpoint?> treatmentPlanCheckpoint() =>
      _unsupportedCheckpoint();

  Future<LifeMateLocalSyncCheckpoint?> treatmentOccurrenceCheckpoint() =>
      _unsupportedCheckpoint();

  Future<List<LifeMateLocalProjectionRecord>> careEventProjections() =>
      _unsupportedProjections();

  Future<List<LifeMateLocalProjectionRecord>> treatmentPlanProjections() =>
      _unsupportedProjections();

  Future<List<LifeMateLocalProjectionRecord>>
  treatmentOccurrenceProjections() => _unsupportedProjections();

  Future<LifeMateProjectionReconcileResult> applyCareEventPage({
    required LifeMateProjectionPullPage page,
    LifeMateBeforeProjectionCheckpoint? beforeCheckpoint,
  }) => _unsupportedReconcile();

  Future<LifeMateProjectionReconcileResult> applyTreatmentPlanPage({
    required LifeMateProjectionPullPage page,
    LifeMateBeforeProjectionCheckpoint? beforeCheckpoint,
  }) => _unsupportedReconcile();

  Future<LifeMateProjectionReconcileResult> applyTreatmentOccurrencePage({
    required LifeMateProjectionPullPage page,
    LifeMateBeforeProjectionCheckpoint? beforeCheckpoint,
  }) => _unsupportedReconcile();

  Future<void> cacheWellMateHomeSnapshot({
    required DateTime fromDate,
    required DateTime toDate,
    required Iterable<Map<String, dynamic>> treatmentPlans,
    required Iterable<Map<String, dynamic>> treatmentOccurrences,
  }) => Future<void>.error(_unsupported());

  Future<Map<String, dynamic>?> readWellMateHomeSnapshot({
    required DateTime fromDate,
    required DateTime toDate,
  }) => Future<Map<String, dynamic>?>.error(_unsupported());

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
  }) => Future<void>.error(_unsupported());

  Future<int> pendingMutationCount() => Future<int>.value(0);

  Future<Map<String, String>> pendingAdherenceStates() =>
      Future<Map<String, String>>.value(const <String, String>{});

  Future<void> purgeCurrentAccount({
    required bool discardPendingAndCachedData,
  }) => Future<void>.error(_unsupported());

  void close() {}

  Future<LifeMateLocalSyncCheckpoint?> _unsupportedCheckpoint() =>
      Future<LifeMateLocalSyncCheckpoint?>.error(_unsupported());

  Future<List<LifeMateLocalProjectionRecord>> _unsupportedProjections() =>
      Future<List<LifeMateLocalProjectionRecord>>.error(_unsupported());

  Future<LifeMateProjectionReconcileResult> _unsupportedReconcile() =>
      Future<LifeMateProjectionReconcileResult>.error(_unsupported());

  UnsupportedError _unsupported() => UnsupportedError(
    'Protected offline health execution is unavailable on web.',
  );
}
