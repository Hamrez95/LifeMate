import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_core/lifemate_core.dart';
import 'package:timezone/timezone.dart' as tz;

void main() {
  final now = DateTime.utc(2026, 9, 5, 8);
  const details = NotificationDetails(
    android: AndroidNotificationDetails('test', 'Test reminders'),
  );

  LifeMateLocalReminder reminder(String recordKey, int revision) =>
      LifeMateLocalReminder(
        sourceOccurrenceKey: 'care:$recordKey:2026-09-06T10:00',
        sourceRevision: revision,
        triggerUtc: now.add(const Duration(hours: 2)),
        title: 'Private reminder',
        body: 'Open LifeMate to review.',
        notificationDetails: details,
        payload: 'record:$recordKey',
      );

  test('reconciles only affected projection reminder state', () async {
    final platform = _FakePlatform();
    final registry = _MemoryRegistry();
    final affectedOld = reminder('affected', 1);
    final affectedCurrent = reminder('affected', 2);
    final unrelated = reminder('unrelated', 1);
    registry.values[affectedOld.scheduleKey] = _persisted(affectedOld);
    registry.values[unrelated.scheduleKey] = _persisted(unrelated);
    platform.pending.addAll([
      PendingNotificationRequest(
        affectedOld.notificationId,
        'private',
        'private',
        'record:affected',
      ),
      PendingNotificationRequest(
        unrelated.notificationId,
        'private',
        'private',
        'record:unrelated',
      ),
    ]);

    final scheduler = LifeMateLocalReminderScheduler(
      platform: platform,
      registry: registry,
      now: () => now,
    );
    final reconciler = LifeMateAffectedReminderReconciler(
      scheduler: scheduler,
      projector: (recordKey) async => [affectedCurrent],
    );

    final result = await reconciler.reconcile(
      affectedRecordKeys: const ['affected'],
      timeZone: 'UTC',
      ownsPendingReminder: (request, affected) =>
          affected.any((key) => request.payload == 'record:$key'),
      ownsPersistedReminder: (persisted, affected) =>
          affected.any((key) => persisted.scheduleKey.startsWith('care:$key:')),
    );

    expect(result.cancelledCount, 1);
    expect(result.scheduledCount, 1);
    expect(platform.cancelled, contains(affectedOld.notificationId));
    expect(platform.cancelled, isNot(contains(unrelated.notificationId)));
    expect(registry.values.containsKey(affectedOld.scheduleKey), isFalse);
    expect(registry.values.containsKey(affectedCurrent.scheduleKey), isTrue);
    expect(registry.values.containsKey(unrelated.scheduleKey), isTrue);
  });

  test('empty affected set is a no-op', () async {
    final platform = _FakePlatform();
    var projectorCalls = 0;
    final reconciler = LifeMateAffectedReminderReconciler(
      scheduler: LifeMateLocalReminderScheduler(
        platform: platform,
        now: () => now,
      ),
      projector: (_) async {
        projectorCalls += 1;
        return const <LifeMateLocalReminder>[];
      },
    );

    final result = await reconciler.reconcile(
      affectedRecordKeys: const [' ', ''],
      timeZone: 'UTC',
      ownsPendingReminder: (_, _) => true,
      ownsPersistedReminder: (_, _) => true,
    );

    expect(projectorCalls, 0);
    expect(platform.pendingReads, 0);
    expect(result.scheduledCount, 0);
    expect(result.cancelledCount, 0);
  });
}

LifeMatePersistedReminder _persisted(LifeMateLocalReminder reminder) =>
    LifeMatePersistedReminder(
      scheduleKey: reminder.scheduleKey,
      notificationId: reminder.notificationId,
      sourceRevision: reminder.sourceRevision,
      triggerUtc: reminder.triggerUtc,
      accuracy: reminder.accuracy,
    );

final class _FakePlatform implements LifeMateReminderPlatform {
  final List<PendingNotificationRequest> pending = [];
  final List<int> cancelled = [];
  final List<int> scheduled = [];
  int pendingReads = 0;

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    pending.removeWhere((request) => request.id == id);
  }

  @override
  Future<List<PendingNotificationRequest>> pendingNotificationRequests() async {
    pendingReads += 1;
    return List<PendingNotificationRequest>.from(pending);
  }

  @override
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime scheduledDate,
    required NotificationDetails notificationDetails,
    required AndroidScheduleMode androidScheduleMode,
    String? payload,
  }) async {
    scheduled.add(id);
  }
}

final class _MemoryRegistry implements LifeMateReminderRegistry {
  final Map<String, LifeMatePersistedReminder> values = {};

  @override
  Future<void> delete(String scheduleKey) async {
    values.remove(scheduleKey);
  }

  @override
  Future<List<LifeMatePersistedReminder>> list() async =>
      values.values.toList(growable: false);

  @override
  Future<void> put(LifeMatePersistedReminder reminder) async {
    values[reminder.scheduleKey] = reminder;
  }
}
