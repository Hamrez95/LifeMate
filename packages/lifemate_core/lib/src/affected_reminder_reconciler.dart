import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'local_reminder_scheduler.dart';

/// Produces the complete desired reminder set for one server projection record.
typedef LifeMateReminderProjector =
    Future<Iterable<LifeMateLocalReminder>> Function(String recordKey);

/// Maps a persisted reminder back to the canonical projection record that owns
/// it. This intentionally works on opaque local keys only; notification content
/// must not be used as identity.
typedef LifeMatePersistedReminderOwner =
    bool Function(
      LifeMatePersistedReminder reminder,
      Set<String> affectedRecordKeys,
    );

/// Maps an OS pending notification back to an affected canonical projection.
typedef LifeMatePendingReminderOwner =
    bool Function(
      PendingNotificationRequest request,
      Set<String> affectedRecordKeys,
    );

/// Reconciles only reminders whose canonical source projections changed.
///
/// Incremental server pull pages return affected record keys. Re-projecting only
/// those records avoids rebuilding unrelated schedules while preserving the
/// shared #830 execution engine. Callers must provide opaque identity matchers;
/// notification title/body is never inspected and PHI is never logged.
final class LifeMateAffectedReminderReconciler {
  LifeMateAffectedReminderReconciler({
    required LifeMateLocalReminderScheduler scheduler,
    required LifeMateReminderProjector projector,
  }) : _scheduler = scheduler,
       _projector = projector;

  final LifeMateLocalReminderScheduler _scheduler;
  final LifeMateReminderProjector _projector;

  Future<LifeMateReminderSyncResult> reconcile({
    required Iterable<String> affectedRecordKeys,
    required String timeZone,
    required LifeMatePendingReminderOwner ownsPendingReminder,
    required LifeMatePersistedReminderOwner ownsPersistedReminder,
    bool Function(PendingNotificationRequest request)? preservePendingRequest,
    bool? exactAlarmGranted,
  }) async {
    final normalized = affectedRecordKeys
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    if (normalized.isEmpty) {
      return const LifeMateReminderSyncResult(
        scheduledCount: 0,
        cancelledCount: 0,
        skippedCount: 0,
        inexactFallbackScheduleKeys: <String>[],
      );
    }

    final desired = <LifeMateLocalReminder>[];
    for (final recordKey in normalized) {
      desired.addAll(await _projector(recordKey));
    }

    return _scheduler.sync(
      reminders: desired,
      timeZone: timeZone,
      ownsPendingRequest: (request) => ownsPendingReminder(request, normalized),
      ownsPersistedReminder: (reminder) =>
          ownsPersistedReminder(reminder, normalized),
      preservePendingRequest: preservePendingRequest,
      exactAlarmGranted: exactAlarmGranted,
    );
  }
}
