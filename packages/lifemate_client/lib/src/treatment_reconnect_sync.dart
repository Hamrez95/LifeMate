import 'durable_lifemate_api_client.dart';
import 'offline_sync_result.dart';

typedef LifeMateTreatmentReminderReconciler = Future<void> Function(
  Map<String, dynamic> serverSnapshot,
);

/// Privacy-minimal outcome for one treatment reconnect cycle. It deliberately
/// contains no Account/Person/treatment identifiers or health payloads.
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

  /// Reminder regeneration is safe only after authoritative server refresh and
  /// when replay has no unresolved/rejected work. This intentionally fails
  /// closed rather than projecting a locally accepted treatment edit as if the
  /// server had confirmed it.
  bool get readyForReminderReconciliation =>
      serverRefreshed &&
      replay.conflicts == 0 &&
      replay.terminalRejected == 0 &&
      replay.retainedForRetry == 0 &&
      replay.pendingRemaining == 0;
}

extension LifeMateDurableTreatmentReconnect on DurableLifeMateApiClient {
  /// Replays accepted local mutations, then refreshes the canonical WellMate
  /// treatment window. A cached fallback is never treated as server refresh.
  ///
  /// When a replay receives 409 the durable conflict remains explicit through
  /// [LifeMateTreatmentReconnectResult.hasConflict]. The server snapshot is
  /// still refreshed when reachable so UI can present current canonical truth,
  /// but reminder regeneration is withheld until the conflict is resolved.
  Future<LifeMateTreatmentReconnectResult> reconcileTreatmentAfterReconnect({
    required DateTime fromDate,
    required DateTime toDate,
    LifeMateTreatmentReminderReconciler? reconcileReminders,
  }) async {
    final replay = await flushPendingMutationsDetailed();
    final snapshot = await getHomeSnapshot(fromDate: fromDate, toDate: toDate);
    final serverRefreshed = snapshot['offlineCached'] != true;

    final preliminary = LifeMateTreatmentReconnectResult(
      replay: replay,
      serverRefreshed: serverRefreshed,
      remindersReconciled: false,
    );
    if (!preliminary.readyForReminderReconciliation ||
        reconcileReminders == null) {
      return preliminary;
    }

    await reconcileReminders(snapshot);
    return LifeMateTreatmentReconnectResult(
      replay: replay,
      serverRefreshed: true,
      remindersReconciled: true,
    );
  }
}
