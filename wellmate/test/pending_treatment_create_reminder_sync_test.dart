import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_core/lifemate_reminders.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:wellmate/providers/pending_treatment_create_reminder_sync.dart';

void main() {
  final nowUtc = DateTime.utc(2026, 9, 7, 4);

  Map<String, dynamic> pendingCreate() => <String, dynamic>{
    'pendingSync': true,
    'clientRequestId': 'private-request-id',
    'startDate': '2026-09-07',
    'endDate': '2026-09-07',
    'timeZone': 'Asia/Tehran',
    'patientReminderMinutesBefore': 30,
    'recurrence': <String, dynamic>{'enabled': false},
    'schedules': <Map<String, dynamic>>[
      <String, dynamic>{'dayOfWeek': 'monday', 'localTime': '09:00'},
    ],
  };

  test('schedules generic no-action reminder through shared scheduler', () async {
    final platform = _FakePlatform();
    final scheduler = LifeMateLocalReminderScheduler(
      platform: platform,
      now: () => nowUtc,
    );
    final sync = PendingTreatmentCreateReminderSync(scheduler: scheduler);

    final result = await sync.sync(
      pendingCreates: <Map<String, dynamic>>[pendingCreate()],
      nowUtc: nowUtc,
      schedulingTimeZone: 'Asia/Tehran',
      isPersian: false,
      exactAlarmGranted: true,
    );

    expect(result.scheduledCount, 1);
    expect(platform.scheduled, hasLength(1));
    final call = platform.scheduled.single;
    expect(call.title, 'LifeMate reminder');
    expect(call.body, 'You have a scheduled health task.');
    expect(call.payload, startsWith(PendingTreatmentCreateReminderSync.payloadPrefix));
    expect(call.payload, isNot(contains('private-request-id')));
    expect(call.details.android?.actions ?? const <AndroidNotificationAction>[], isEmpty);
    expect(call.mode, AndroidScheduleMode.exactAllowWhileIdle);
  });

  test('reconciliation cancels only provisional pending-treatment reminders', () async {
    final platform = _FakePlatform();
    platform.pending.addAll(<PendingNotificationRequest>[
      const PendingNotificationRequest(
        11,
        'old',
        'old',
        'lifemate-pending-treatment-create:stale',
      ),
      const PendingNotificationRequest(12, 'other', 'other', 'lifemate-reminder:other'),
    ]);
    final scheduler = LifeMateLocalReminderScheduler(
      platform: platform,
      now: () => nowUtc,
    );
    final sync = PendingTreatmentCreateReminderSync(scheduler: scheduler);

    await sync.sync(
      pendingCreates: const <Map<String, dynamic>>[],
      nowUtc: nowUtc,
      schedulingTimeZone: 'UTC',
      isPersian: true,
    );

    expect(platform.cancelled, contains(11));
    expect(platform.cancelled, isNot(contains(12)));
  });

  test('exact-alarm denial degrades to shared inexact fallback', () async {
    final platform = _FakePlatform();
    final scheduler = LifeMateLocalReminderScheduler(
      platform: platform,
      now: () => nowUtc,
    );
    final sync = PendingTreatmentCreateReminderSync(scheduler: scheduler);

    final result = await sync.sync(
      pendingCreates: <Map<String, dynamic>>[pendingCreate()],
      nowUtc: nowUtc,
      schedulingTimeZone: 'Asia/Tehran',
      isPersian: false,
      exactAlarmGranted: false,
    );

    expect(result.usedInexactFallback, isTrue);
    expect(platform.scheduled.single.mode, AndroidScheduleMode.inexactAllowWhileIdle);
  });
}

final class _ScheduledCall {
  const _ScheduledCall({
    required this.id,
    required this.title,
    required this.body,
    required this.details,
    required this.mode,
    required this.payload,
  });

  final int id;
  final String title;
  final String body;
  final NotificationDetails details;
  final AndroidScheduleMode mode;
  final String? payload;
}

final class _FakePlatform implements LifeMateReminderPlatform {
  final List<PendingNotificationRequest> pending = <PendingNotificationRequest>[];
  final List<int> cancelled = <int>[];
  final List<_ScheduledCall> scheduled = <_ScheduledCall>[];

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
    scheduled.add(
      _ScheduledCall(
        id: id,
        title: title,
        body: body,
        details: notificationDetails,
        mode: androidScheduleMode,
        payload: payload,
      ),
    );
  }
}
