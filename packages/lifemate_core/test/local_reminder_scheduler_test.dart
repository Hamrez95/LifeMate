import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_core/lifemate_reminders.dart';
import 'package:timezone/timezone.dart' as tz;

void main() {
  final now = DateTime.utc(2026, 9, 5, 8);
  const details = NotificationDetails(
    android: AndroidNotificationDetails('test', 'Test reminders'),
  );

  LifeMateLocalReminder reminder({
    String source = 'occurrence-1',
    int revision = 1,
    DateTime? trigger,
    LifeMateReminderAccuracy accuracy = LifeMateReminderAccuracy.exact,
  }) => LifeMateLocalReminder(
    sourceOccurrenceKey: source,
    sourceRevision: revision,
    triggerUtc: trigger ?? now.add(const Duration(hours: 2)),
    title: 'Private reminder',
    body: 'Open LifeMate to review.',
    notificationDetails: details,
    payload: 'opaque-payload',
    accuracy: accuracy,
  );

  test('stable notification identity includes source revision', () {
    final first = LifeMateReminderIdentity.notificationIdFor(
      'occurrence-1',
      sourceRevision: 4,
    );
    final same = LifeMateReminderIdentity.notificationIdFor(
      'occurrence-1',
      sourceRevision: 4,
    );
    final edited = LifeMateReminderIdentity.notificationIdFor(
      'occurrence-1',
      sourceRevision: 5,
    );

    expect(first, same);
    expect(edited, isNot(first));
    expect(first, inInclusiveRange(0, 0x7fffffff));
  });

  test('edit reconciliation removes superseded future reminder only', () async {
    final platform = _FakeReminderPlatform();
    final old = reminder(revision: 1);
    final current = reminder(revision: 2);
    platform.pending.add(
      PendingNotificationRequest(old.notificationId, 'old', 'old', 'owned:old'),
    );

    final scheduler = LifeMateLocalReminderScheduler(
      platform: platform,
      now: () => now,
    );
    final result = await scheduler.sync(
      reminders: [current],
      timeZone: 'Asia/Tehran',
      ownsPendingRequest: (request) =>
          request.payload?.startsWith('owned:') == true,
    );

    expect(platform.cancelled, contains(old.notificationId));
    expect(platform.scheduled.single.id, current.notificationId);
    expect(result.cancelledCount, 1);
    expect(result.scheduledCount, 1);
  });

  test('latest revision wins and horizon is bounded', () async {
    final platform = _FakeReminderPlatform();
    final scheduler = LifeMateLocalReminderScheduler(
      platform: platform,
      horizon: const Duration(days: 7),
      now: () => now,
    );

    final result = await scheduler.sync(
      reminders: [
        reminder(revision: 1),
        reminder(revision: 2),
        reminder(source: 'too-late', trigger: now.add(const Duration(days: 8))),
        reminder(
          source: 'past',
          trigger: now.subtract(const Duration(minutes: 1)),
        ),
      ],
      timeZone: 'UTC',
    );

    expect(platform.scheduled, hasLength(1));
    expect(platform.scheduled.single.id, reminder(revision: 2).notificationId);
    expect(result.skippedCount, 3);
  });

  test(
    'known exact-alarm denial falls back without dropping reminder',
    () async {
      final platform = _FakeReminderPlatform();
      final current = reminder();
      final scheduler = LifeMateLocalReminderScheduler(
        platform: platform,
        now: () => now,
      );

      final result = await scheduler.sync(
        reminders: [current],
        timeZone: 'Asia/Tehran',
        exactAlarmGranted: false,
      );

      expect(
        platform.scheduled.single.mode,
        AndroidScheduleMode.inexactAllowWhileIdle,
      );
      expect(result.inexactFallbackScheduleKeys, [current.scheduleKey]);
    },
  );

  test('runtime exact-alarm failure retries once as inexact', () async {
    final platform = _FakeReminderPlatform(throwOnExact: true);
    final current = reminder();
    final scheduler = LifeMateLocalReminderScheduler(
      platform: platform,
      now: () => now,
    );

    final result = await scheduler.sync(
      reminders: [current],
      timeZone: 'Asia/Tehran',
    );

    expect(platform.scheduleAttempts, 2);
    expect(
      platform.scheduled.single.mode,
      AndroidScheduleMode.inexactAllowWhileIdle,
    );
    expect(result.usedInexactFallback, isTrue);
  });

  test(
    'preserved snooze is not cancelled during owner reconciliation',
    () async {
      final platform = _FakeReminderPlatform();
      const snoozeId = 73;
      platform.pending.add(
        const PendingNotificationRequest(
          snoozeId,
          'snooze',
          'snooze',
          'snooze:keep',
        ),
      );
      final scheduler = LifeMateLocalReminderScheduler(
        platform: platform,
        now: () => now,
      );

      await scheduler.sync(
        reminders: const [],
        timeZone: 'UTC',
        ownsPendingRequest: (_) => true,
        preservePendingRequest: (request) => request.payload == 'snooze:keep',
      );

      expect(platform.cancelled, isNot(contains(snoozeId)));
    },
  );

  test(
    'registry stores execution metadata and deletes stale revisions',
    () async {
      final platform = _FakeReminderPlatform();
      final registry = _MemoryReminderRegistry();
      final stale = reminder(revision: 1);
      registry.values[stale.scheduleKey] = LifeMatePersistedReminder(
        scheduleKey: stale.scheduleKey,
        notificationId: stale.notificationId,
        sourceRevision: stale.sourceRevision,
        triggerUtc: stale.triggerUtc,
        accuracy: stale.accuracy,
      );
      final current = reminder(revision: 2);
      final scheduler = LifeMateLocalReminderScheduler(
        platform: platform,
        registry: registry,
        now: () => now,
      );

      await scheduler.sync(reminders: [current], timeZone: 'UTC');

      expect(registry.values.containsKey(stale.scheduleKey), isFalse);
      expect(registry.values.containsKey(current.scheduleKey), isTrue);
    },
  );
}

final class _ScheduledCall {
  const _ScheduledCall({required this.id, required this.mode});

  final int id;
  final AndroidScheduleMode mode;
}

final class _FakeReminderPlatform implements LifeMateReminderPlatform {
  _FakeReminderPlatform({this.throwOnExact = false});

  final bool throwOnExact;
  final List<PendingNotificationRequest> pending = [];
  final List<int> cancelled = [];
  final List<_ScheduledCall> scheduled = [];
  int scheduleAttempts = 0;

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    pending.removeWhere((request) => request.id == id);
  }

  @override
  Future<List<PendingNotificationRequest>>
  pendingNotificationRequests() async =>
      List<PendingNotificationRequest>.from(pending);

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
    scheduleAttempts += 1;
    if (throwOnExact &&
        androidScheduleMode == AndroidScheduleMode.exactAllowWhileIdle) {
      throw PlatformException(code: 'exact_alarms_not_permitted');
    }
    scheduled.add(_ScheduledCall(id: id, mode: androidScheduleMode));
  }
}

final class _MemoryReminderRegistry implements LifeMateReminderRegistry {
  final Map<String, LifeMatePersistedReminder> values = {};

  @override
  Future<void> delete(String scheduleKey) async {
    values.remove(scheduleKey);
  }

  @override
  Future<List<LifeMatePersistedReminder>> list() async =>
      values.values.toList();

  @override
  Future<void> put(LifeMatePersistedReminder reminder) async {
    values[reminder.scheduleKey] = reminder;
  }
}
