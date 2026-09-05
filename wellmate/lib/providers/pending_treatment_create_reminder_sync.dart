import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:lifemate_core/lifemate_reminders.dart';

import 'pending_treatment_create_reminder_projection.dart';

/// Reconciles only provisional reminders derived from durable pending treatment
/// creates. These reminders deliberately expose no adherence action because a
/// pending create does not yet have canonical server occurrence identifiers.
final class PendingTreatmentCreateReminderSync {
  PendingTreatmentCreateReminderSync({
    required LifeMateLocalReminderScheduler scheduler,
  }) : _scheduler = scheduler;

  static const sourcePrefix = 'wellmate:pending-treatment-create:';
  static const payloadPrefix = 'lifemate-pending-treatment-create:';

  final LifeMateLocalReminderScheduler _scheduler;

  Future<LifeMateReminderSyncResult> sync({
    required Iterable<Map<String, dynamic>> pendingCreates,
    required DateTime nowUtc,
    required String schedulingTimeZone,
    required bool isPersian,
    bool? exactAlarmGranted,
  }) {
    final projections = projectPendingTreatmentCreateReminders(
      pendingCreates: pendingCreates,
      nowUtc: nowUtc,
      horizon: _scheduler.horizon,
    );
    final reminders = projections.map(
      (projection) => LifeMateLocalReminder(
        sourceOccurrenceKey: projection.sourceOccurrenceKey,
        sourceRevision: projection.sourceRevision,
        triggerUtc: projection.triggerUtc,
        title: isPersian ? 'یادآوری LifeMate' : 'LifeMate reminder',
        body: isPersian
            ? 'یک کار سلامت برنامه‌ریزی‌شده دارید.'
            : 'You have a scheduled health task.',
        notificationDetails: _notificationDetails(isPersian),
        payload: '$payloadPrefix${projection.sourceOccurrenceKey}',
        accuracy: LifeMateReminderAccuracy.exact,
        allowInexactFallback: true,
      ),
    );

    return _scheduler.sync(
      reminders: reminders,
      timeZone: schedulingTimeZone,
      ownsPendingRequest: ownsPendingRequest,
      ownsPersistedReminder: ownsPersistedReminder,
      exactAlarmGranted: exactAlarmGranted,
    );
  }

  static bool ownsPendingRequest(PendingNotificationRequest request) =>
      request.payload?.startsWith(payloadPrefix) == true;

  static bool ownsPersistedReminder(LifeMatePersistedReminder reminder) =>
      reminder.scheduleKey.startsWith(sourcePrefix);

  static NotificationDetails _notificationDetails(bool isPersian) =>
      NotificationDetails(
        android: AndroidNotificationDetails(
          'wellmate_pending_treatment_create',
          isPersian ? 'یادآوری‌های سلامت' : 'Health reminders',
          channelDescription: isPersian
              ? 'یادآوری‌های محلی برای برنامه‌های سلامت در انتظار همگام‌سازی'
              : 'Local reminders for health plans pending synchronization',
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.reminder,
          visibility: NotificationVisibility.private,
        ),
      );
}
