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

  Future<void> adoptSharedOfflineRuntime({
    required String environmentId,
    required String accountId,
    required String personId,
    required String legacyAuthenticatedAccountId,
    required String timeZone,
    LifeMateLocalHealthStore? localStore,
    LifeMateMutationStorage? legacyStorage,
  }) => Future<void>.error(
    UnsupportedError('Protected offline health execution is unavailable on web.'),
  );

  Future<String> enqueueTreatmentPlanEdit({
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
    LifeMateLocalHealthStore? localStore,
  }) => Future<String>.error(
    UnsupportedError('Protected offline health execution is unavailable on web.'),
  );

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
    UnsupportedError('Protected offline health execution is unavailable on web.'),
  );

  Future<int> pendingMutationCount() async => 0;
}
