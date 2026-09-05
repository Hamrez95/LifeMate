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
    required String source,
    required int revision,
    required DateTime trigger,
  }) => LifeMateLocalReminder(
    sourceOccurrenceKey: source,
    sourceRevision: revision,
    triggerUtc: trigger,
    title: 'Private reminder',
    body: 'Open LifeMate to review.',
    notificationDetails: details,
    payload: 'owned:$source',
  );

  test('clean sync leaves unchanged pending reminders untouched', () async {
    final platform = _FakeReminderPlatform();
    final unchanged = reminder(
      source: 'group-a',
      revision: 4,
      trigger: now.add(const Duration(hours: 2)),
    );
    platform.pending.add(
      PendingNotificationRequest(
        unchanged.notificationId,
        'private',
        'private',
        'owned:group-a',
      ),
    );
    final scheduler = LifeMateLocalReminderScheduler(
      platform: platform,
      now: () => now,
    );

    final result = await scheduler.sync(
      reminders: [unchanged],
      timeZone: 'UTC',
      ownsPendingRequest: (request) =>
          request.payload?.startsWith('owned:') == true,
    );

    expect(platform.cancelled, isEmpty);
    expect(platform.scheduled, isEmpty);
    expect(result.cancelledCount, 0);
    expect(result.scheduledCount, 0);
    expect(result.skippedCount, 1);
  });

  test('changed group updates while unrelated pending group is preserved', () async {
    final platform = _FakeReminderPlatform();
    final oldChanged = reminder(
      source: 'group-changed',
      revision: 1,
      trigger: now.add(const Duration(hours: 2)),
    );
    final newChanged = reminder(
      source: 'group-changed',
      revision: 2,
      trigger: now.add(const Duration(hours: 3)),
    );
    final unchanged = reminder(
      source: 'group-stable',
      revision: 7,
      trigger: now.add(const Duration(hours: 4)),
    );
    platform.pending.addAll([
      PendingNotificationRequest(
        oldChanged.notificationId,
        'private',
        'private',
        'owned:group-changed',
      ),
      PendingNotificationRequest(
        unchanged.notificationId,
        'private',
        'private',
        'owned:group-stable',
      ),
    ]);
    final scheduler = LifeMateLocalReminderScheduler(
      platform: platform,
      now: () => now,
    );

    final result = await scheduler.sync(
      reminders: [newChanged, unchanged],
      timeZone: 'UTC',
      ownsPendingRequest: (request) =>
          request.payload?.startsWith('owned:') == true,
    );

    expect(platform.cancelled, contains(oldChanged.notificationId));
    expect(platform.cancelled, isNot(contains(unchanged.notificationId)));
    expect(platform.scheduled.map((call) => call.id), [newChanged.notificationId]);
    expect(result.cancelledCount, 1);
    expect(result.scheduledCount, 1);
    expect(result.skippedCount, 1);
  });
}

final class _ScheduledCall {
  const _ScheduledCall(this.id);
  final int id;
}

final class _FakeReminderPlatform implements LifeMateReminderPlatform {
  final List<PendingNotificationRequest> pending = [];
  final List<int> cancelled = [];
  final List<_ScheduledCall> scheduled = [];

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    pending.removeWhere((request) => request.id == id);
  }

  @override
  Future<List<PendingNotificationRequest>> pendingNotificationRequests() async =>
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
    scheduled.add(_ScheduledCall(id));
  }
}
