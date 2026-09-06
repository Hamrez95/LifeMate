import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:lifemate_core/lifemate_core.dart';

import 'care_event_projection_sync_web.dart';
import 'lifemate_api_client.dart';
import 'offline_mutation_queue.dart' show LifeMateMutationStorage;
import 'offline_sync_result.dart';

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

final ValueNotifier<LifeMateOfflineSyncResult?> lifeMateOfflineSyncResult =
    ValueNotifier<LifeMateOfflineSyncResult?>(null);

typedef LifeMateTreatmentReminderReconciler =
    Future<void> Function(Map<String, dynamic> serverSnapshot);

final class LifeMateTreatmentReconnectResult {
  const LifeMateTreatmentReconnectResult({
    required this.replay,
    required this.serverRefreshed,
    required this.remindersReconciled,
  });

  final LifeMateOfflineSyncResult replay;
  final bool serverRefreshed;
  final bool remindersReconciled;

  bool get hasConflict => replay.conflicts > 0;

  bool get readyForReminderReconciliation =>
      serverRefreshed &&
      replay.conflicts == 0 &&
      replay.terminalRejected == 0 &&
      replay.retainedForRetry == 0 &&
      replay.pendingRemaining == 0;
}

/// Online-only browser client. It deliberately does not emulate the protected
/// native mutation outbox, encrypted health store, or projection cursor in
/// browser storage. Network failures therefore fail normally instead of being
/// persisted insecurely.
class DurableLifeMateApiClient extends LifeMateApiClient {
  DurableLifeMateApiClient({
    required Uri baseUri,
    required AccessTokenProvider accessToken,
    required String? Function() accountId,
    Object? queue,
    http.Client? innerHttpClient,
  }) : super(
         baseUri: baseUri,
         accessToken: accessToken,
         httpClient: innerHttpClient,
       );

  /// Browser builds deliberately never expose a protected local PHI namespace.
  LifeMateLocalNamespace? get activeOfflineNamespace => null;

  Future<void> adoptSharedOfflineRuntime({
    required String environmentId,
    required String accountId,
    required String personId,
    required String legacyAuthenticatedAccountId,
    required String timeZone,
    LifeMateLocalHealthStore? localStore,
    LifeMateMutationStorage? legacyStorage,
  }) => Future<void>.error(
    UnsupportedError(
      'Protected offline health execution is unavailable on web.',
    ),
  );

  Future<List<Map<String, dynamic>>> pendingOfflineTreatmentPlanCreates() =>
      Future<List<Map<String, dynamic>>>.error(
        UnsupportedError(
          'Protected offline health execution is unavailable on web.',
        ),
      );

  Future<void> enqueueOfflineCareEventCreate({
    required String clientRequestId,
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
    required String timeZone,
    required int patientReminderMinutesBefore,
    required int caregiverReminderMinutesBefore,
    DateTime? createdAtUtc,
  }) => Future<void>.error(
    UnsupportedError(
      'Protected offline health execution is unavailable on web.',
    ),
  );

  Future<void> enqueueOfflineTreatmentPlanCreate({
    required String clientRequestId,
    required String medicationId,
    required String doseText,
    String? instructions,
    required DateTime startDate,
    DateTime? endDate,
    required String timeZone,
    required List<Map<String, String>> schedules,
    required int patientReminderMinutesBefore,
    required int caregiverReminderMinutesBefore,
    DateTime? createdAtUtc,
  }) => Future<void>.error(
    UnsupportedError(
      'Protected offline health execution is unavailable on web.',
    ),
  );

  Future<void> enqueueOfflineTreatmentPlanEdit({
    required String clientRequestId,
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
  }) => Future<void>.error(
    UnsupportedError(
      'Protected offline health execution is unavailable on web.',
    ),
  );

  Future<LifeMateTreatmentReconnectResult> reconcileTreatmentAfterReconnect({
    required DateTime fromDate,
    required DateTime toDate,
    LifeMateTreatmentReminderReconciler? reconcileReminders,
  }) async {
    final replay = await flushPendingMutationsDetailed();
    final snapshot = await getHomeSnapshot(fromDate: fromDate, toDate: toDate);
    final preliminary = LifeMateTreatmentReconnectResult(
      replay: replay,
      serverRefreshed: true,
      remindersReconciled: false,
    );
    if (reconcileReminders == null) return preliminary;
    await reconcileReminders(snapshot);
    return LifeMateTreatmentReconnectResult(
      replay: replay,
      serverRefreshed: true,
      remindersReconciled: true,
    );
  }

  Future<int> flushPendingMutations() async => 0;

  Future<LifeMateOfflineSyncResult> flushPendingMutationsDetailed() async {
    const result = LifeMateOfflineSyncResult();
    lifeMateOfflineSyncResult.value = result;
    return result;
  }

  Future<LifeMateCareEventProjectionSyncResult> syncCareEventProjections({
    int pageSize = 100,
    int maximumPages = 10,
    LifeMateBeforeProjectionCheckpoint? beforeCheckpoint,
  }) => Future<LifeMateCareEventProjectionSyncResult>.error(
    UnsupportedError(
      'Protected offline health execution is unavailable on web.',
    ),
  );

  Future<int> pendingMutationCount() async => 0;
}
