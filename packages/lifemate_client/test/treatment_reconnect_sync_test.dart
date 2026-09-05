import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test('conflict refresh remains explicit and blocks reminder reconciliation', () {
    const result = LifeMateTreatmentReconnectResult(
      replay: LifeMateOfflineSyncResult(conflicts: 1),
      serverRefreshed: true,
      remindersReconciled: false,
    );

    expect(result.hasConflict, isTrue);
    expect(result.readyForReminderReconciliation, isFalse);
    expect(result.remindersReconciled, isFalse);
  });

  test('cached fallback is never treated as authoritative reminder refresh', () {
    const result = LifeMateTreatmentReconnectResult(
      replay: LifeMateOfflineSyncResult(),
      serverRefreshed: false,
      remindersReconciled: false,
    );

    expect(result.hasConflict, isFalse);
    expect(result.readyForReminderReconciliation, isFalse);
  });

  test('clean replay plus server refresh can reconcile reminders', () {
    const result = LifeMateTreatmentReconnectResult(
      replay: LifeMateOfflineSyncResult(),
      serverRefreshed: true,
      remindersReconciled: false,
    );

    expect(result.readyForReminderReconciliation, isTrue);
  });

  test('retry or rejection remains fail-closed for reminder regeneration', () {
    const retrying = LifeMateTreatmentReconnectResult(
      replay: LifeMateOfflineSyncResult(
        retainedForRetry: 1,
        pendingRemaining: 1,
      ),
      serverRefreshed: true,
      remindersReconciled: false,
    );
    const rejected = LifeMateTreatmentReconnectResult(
      replay: LifeMateOfflineSyncResult(terminalRejected: 1),
      serverRefreshed: true,
      remindersReconciled: false,
    );

    expect(retrying.readyForReminderReconciliation, isFalse);
    expect(rejected.readyForReminderReconciliation, isFalse);
  });
}
