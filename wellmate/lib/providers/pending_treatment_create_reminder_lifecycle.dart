import 'package:lifemate_client/lifemate_client.dart';

typedef PendingTreatmentReminderSync = Future<void> Function();
typedef OwnerTreatmentReconnect =
    Future<LifeMateTreatmentReconnectResult?> Function();

/// Keeps provisional treatment-create reminders alive while a durable create is
/// unresolved, and removes/replaces them only after replay + authoritative
/// server refresh is clean enough for canonical reminder reconciliation.
///
/// The first sync makes durable pending creates locally executable while the
/// device is offline. A conflict/retry/terminal failure deliberately skips the
/// cleanup sync, so we never erase the only local reminder window merely because
/// authority could not yet be refreshed. A clean reconnect runs a second sync;
/// at that point the durable outbox no longer projects confirmed creates and the
/// provisional ownership namespace is cancelled/deduplicated safely.
Future<void> reconcilePendingTreatmentReminderLifecycle({
  required PendingTreatmentReminderSync syncPending,
  required OwnerTreatmentReconnect reconnect,
}) async {
  await syncPending();
  final result = await reconnect();
  if (result?.readyForReminderReconciliation == true) {
    await syncPending();
  }
}
