import 'durable_lifemate_api_client_web.dart';
import 'offline_sync_result.dart';

typedef LifeMateTreatmentReminderReconciler = Future<void> Function(
  Map<String, dynamic> serverSnapshot,
);

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

extension LifeMateDurableTreatmentReconnect on DurableLifeMateApiClient {
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
}
