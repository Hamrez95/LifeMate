import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:wellmate/providers/pending_treatment_create_reminder_lifecycle.dart';

void main() {
  test('clean authoritative reconnect cancels stale provisional namespace', () async {
    var syncCalls = 0;

    await reconcilePendingTreatmentReminderLifecycle(
      syncPending: () async => syncCalls += 1,
      reconnect: () async => LifeMateTreatmentReconnectResult(
        replay: const LifeMateOfflineSyncResult(),
        serverRefreshed: true,
        remindersReconciled: true,
      ),
    );

    expect(syncCalls, 2);
  });

  test('conflict keeps provisional reminder ownership intact', () async {
    var syncCalls = 0;

    await reconcilePendingTreatmentReminderLifecycle(
      syncPending: () async => syncCalls += 1,
      reconnect: () async => LifeMateTreatmentReconnectResult(
        replay: const LifeMateOfflineSyncResult(conflicts: 1),
        serverRefreshed: true,
        remindersReconciled: false,
      ),
    );

    expect(syncCalls, 1);
  });

  test('retry or offline refresh keeps provisional reminders', () async {
    for (final result in <LifeMateTreatmentReconnectResult?>[
      LifeMateTreatmentReconnectResult(
        replay: const LifeMateOfflineSyncResult(retainedForRetry: 1, pendingRemaining: 1),
        serverRefreshed: false,
        remindersReconciled: false,
      ),
      null,
    ]) {
      var syncCalls = 0;
      await reconcilePendingTreatmentReminderLifecycle(
        syncPending: () async => syncCalls += 1,
        reconnect: () async => result,
      );
      expect(syncCalls, 1);
    }
  });
}
