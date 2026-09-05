import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

enum LifeMateReminderAccuracy { exact, inexact }

final class LifeMateLocalReminder {
  LifeMateLocalReminder({
    required String sourceOccurrenceKey,
    required this.sourceRevision,
    required DateTime triggerUtc,
    required this.title,
    required this.body,
    required this.notificationDetails,
    required this.payload,
    this.accuracy = LifeMateReminderAccuracy.exact,
    this.allowInexactFallback = true,
  }) : sourceOccurrenceKey = _requireOpaqueKey(sourceOccurrenceKey),
       triggerUtc = triggerUtc.toUtc() {
    if (sourceRevision < 0) {
      throw ArgumentError.value(
        sourceRevision,
        'sourceRevision',
        'sourceRevision must be non-negative.',
      );
    }
  }

  final String sourceOccurrenceKey;
  final int sourceRevision;
  final DateTime triggerUtc;
  final String title;
  final String body;
  final NotificationDetails notificationDetails;
  final String? payload;
  final LifeMateReminderAccuracy accuracy;
  final bool allowInexactFallback;

  String get scheduleKey => '$sourceOccurrenceKey@r$sourceRevision';

  int get notificationId => LifeMateReminderIdentity.notificationIdFor(
    sourceOccurrenceKey,
    sourceRevision: sourceRevision,
  );

  static String _requireOpaqueKey(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(
        value,
        'sourceOccurrenceKey',
        'sourceOccurrenceKey must not be empty.',
      );
    }
    return normalized;
  }
}

abstract final class LifeMateReminderIdentity {
  static int notificationIdFor(
    String sourceOccurrenceKey, {
    required int sourceRevision,
  }) {
    final normalized = sourceOccurrenceKey.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(
        sourceOccurrenceKey,
        'sourceOccurrenceKey',
        'sourceOccurrenceKey must not be empty.',
      );
    }
    if (sourceRevision < 0) {
      throw ArgumentError.value(
        sourceRevision,
        'sourceRevision',
        'sourceRevision must be non-negative.',
      );
    }
    return stableHash('lifemate-reminder-v1|$normalized|r:$sourceRevision');
  }

  static int stableRevisionFor(String value) =>
      stableHash('revision-v1|$value');

  static int stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }
}

final class LifeMatePersistedReminder {
  const LifeMatePersistedReminder({
    required this.scheduleKey,
    required this.notificationId,
    required this.sourceRevision,
    required this.triggerUtc,
    required this.accuracy,
  });

  final String scheduleKey;
  final int notificationId;
  final int sourceRevision;
  final DateTime triggerUtc;
  final LifeMateReminderAccuracy accuracy;
}

abstract interface class LifeMateReminderRegistry {
  Future<List<LifeMatePersistedReminder>> list();

  Future<void> put(LifeMatePersistedReminder reminder);

  Future<void> delete(String scheduleKey);
}

abstract interface class LifeMateReminderPlatform {
  Future<List<PendingNotificationRequest>> pendingNotificationRequests();

  Future<void> cancel(int id);

  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime scheduledDate,
    required NotificationDetails notificationDetails,
    required AndroidScheduleMode androidScheduleMode,
    String? payload,
  });
}

final class FlutterLifeMateReminderPlatform
    implements LifeMateReminderPlatform {
  FlutterLifeMateReminderPlatform(this.plugin);

  final FlutterLocalNotificationsPlugin plugin;

  @override
  Future<List<PendingNotificationRequest>> pendingNotificationRequests() =>
      plugin.pendingNotificationRequests();

  @override
  Future<void> cancel(int id) => plugin.cancel(id);

  @override
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime scheduledDate,
    required NotificationDetails notificationDetails,
    required AndroidScheduleMode androidScheduleMode,
    String? payload,
  }) => plugin.zonedSchedule(
    id,
    title,
    body,
    scheduledDate,
    notificationDetails,
    androidScheduleMode: androidScheduleMode,
    payload: payload,
  );
}

final class LifeMateReminderSyncResult {
  const LifeMateReminderSyncResult({
    required this.scheduledCount,
    required this.cancelledCount,
    required this.skippedCount,
    required this.inexactFallbackScheduleKeys,
  });

  final int scheduledCount;
  final int cancelledCount;
  final int skippedCount;
  final List<String> inexactFallbackScheduleKeys;

  bool get usedInexactFallback => inexactFallbackScheduleKeys.isNotEmpty;
}

final class LifeMateReminderConflictException implements Exception {
  const LifeMateReminderConflictException(this.message);

  final String message;

  @override
  String toString() => 'LifeMateReminderConflictException($message)';
}

final class LifeMateLocalReminderScheduler {
  LifeMateLocalReminderScheduler({
    required LifeMateReminderPlatform platform,
    LifeMateReminderRegistry? registry,
    Duration horizon = const Duration(days: 45),
    int maximumScheduledReminders = 512,
    DateTime Function()? now,
  }) : _platform = platform,
       _registry = registry,
       horizon = horizon,
       maximumScheduledReminders = maximumScheduledReminders,
       _now = now ?? (() => DateTime.now().toUtc()) {
    if (horizon <= Duration.zero) {
      throw ArgumentError.value(horizon, 'horizon');
    }
    if (maximumScheduledReminders < 1) {
      throw ArgumentError.value(
        maximumScheduledReminders,
        'maximumScheduledReminders',
      );
    }
  }

  final LifeMateReminderPlatform _platform;
  final LifeMateReminderRegistry? _registry;
  final Duration horizon;
  final int maximumScheduledReminders;
  final DateTime Function() _now;

  Future<LifeMateReminderSyncResult> sync({
    required Iterable<LifeMateLocalReminder> reminders,
    required String timeZone,
    bool Function(PendingNotificationRequest request)? ownsPendingRequest,
    bool Function(LifeMatePersistedReminder reminder)? ownsPersistedReminder,
    bool Function(PendingNotificationRequest request)? preservePendingRequest,
    bool? exactAlarmGranted,
  }) async {
    tz_data.initializeTimeZones();
    final location = _resolveLocation(timeZone);
    final nowUtc = _now().toUtc();
    final horizonEnd = nowUtc.add(horizon);

    final latestBySource = <String, LifeMateLocalReminder>{};
    var skippedCount = 0;
    for (final reminder in reminders) {
      final previous = latestBySource[reminder.sourceOccurrenceKey];
      if (previous == null) {
        latestBySource[reminder.sourceOccurrenceKey] = reminder;
        continue;
      }
      if (reminder.sourceRevision > previous.sourceRevision) {
        skippedCount += 1;
        latestBySource[reminder.sourceOccurrenceKey] = reminder;
        continue;
      }
      if (reminder.sourceRevision == previous.sourceRevision &&
          reminder.triggerUtc != previous.triggerUtc) {
        throw LifeMateReminderConflictException(
          'The same source revision projected multiple trigger instants.',
        );
      }
      skippedCount += 1;
    }

    final desired =
        latestBySource.values
            .where((reminder) {
              final inWindow =
                  reminder.triggerUtc.isAfter(nowUtc) &&
                  !reminder.triggerUtc.isAfter(horizonEnd);
              if (!inWindow) skippedCount += 1;
              return inWindow;
            })
            .toList(growable: false)
          ..sort((a, b) => a.triggerUtc.compareTo(b.triggerUtc));

    if (desired.length > maximumScheduledReminders) {
      throw LifeMateReminderConflictException(
        'Projected reminders exceed the bounded scheduling limit.',
      );
    }

    final desiredById = <int, LifeMateLocalReminder>{};
    for (final reminder in desired) {
      final existing = desiredById[reminder.notificationId];
      if (existing != null && existing.scheduleKey != reminder.scheduleKey) {
        throw LifeMateReminderConflictException(
          'Stable notification identifier collision detected.',
        );
      }
      desiredById[reminder.notificationId] = reminder;
    }

    var cancelledCount = 0;
    if (ownsPendingRequest != null) {
      final pending = await _platform.pendingNotificationRequests();
      for (final request in pending) {
        if (!ownsPendingRequest(request)) continue;
        if (preservePendingRequest?.call(request) == true) continue;
        if (desiredById.containsKey(request.id)) continue;
        await _platform.cancel(request.id);
        cancelledCount += 1;
      }
    }

    final persisted =
        await _registry?.list() ?? const <LifeMatePersistedReminder>[];
    final desiredScheduleKeys = desired
        .map((value) => value.scheduleKey)
        .toSet();
    for (final previous in persisted) {
      if (ownsPersistedReminder != null &&
          !ownsPersistedReminder(previous)) {
        continue;
      }
      if (!desiredScheduleKeys.contains(previous.scheduleKey)) {
        await _registry?.delete(previous.scheduleKey);
      }
    }

    final fallbacks = <String>[];
    var scheduledCount = 0;
    for (final reminder in desired) {
      await _platform.cancel(reminder.notificationId);
      final scheduledDate = tz.TZDateTime.from(reminder.triggerUtc, location);
      var actualAccuracy = reminder.accuracy;
      var mode = reminder.accuracy == LifeMateReminderAccuracy.exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle;

      if (reminder.accuracy == LifeMateReminderAccuracy.exact &&
          exactAlarmGranted == false) {
        if (!reminder.allowInexactFallback) {
          throw const LifeMateReminderConflictException(
            'Exact alarm access is unavailable and fallback is disabled.',
          );
        }
        mode = AndroidScheduleMode.inexactAllowWhileIdle;
        actualAccuracy = LifeMateReminderAccuracy.inexact;
        fallbacks.add(reminder.scheduleKey);
      }

      try {
        await _platform.schedule(
          id: reminder.notificationId,
          title: reminder.title,
          body: reminder.body,
          scheduledDate: scheduledDate,
          notificationDetails: reminder.notificationDetails,
          androidScheduleMode: mode,
          payload: reminder.payload,
        );
      } on PlatformException {
        if (mode != AndroidScheduleMode.exactAllowWhileIdle ||
            !reminder.allowInexactFallback) {
          rethrow;
        }
        await _platform.schedule(
          id: reminder.notificationId,
          title: reminder.title,
          body: reminder.body,
          scheduledDate: scheduledDate,
          notificationDetails: reminder.notificationDetails,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: reminder.payload,
        );
        actualAccuracy = LifeMateReminderAccuracy.inexact;
        if (!fallbacks.contains(reminder.scheduleKey)) {
          fallbacks.add(reminder.scheduleKey);
        }
      }
      scheduledCount += 1;
      await _registry?.put(
        LifeMatePersistedReminder(
          scheduleKey: reminder.scheduleKey,
          notificationId: reminder.notificationId,
          sourceRevision: reminder.sourceRevision,
          triggerUtc: reminder.triggerUtc,
          accuracy: actualAccuracy,
        ),
      );
    }

    return LifeMateReminderSyncResult(
      scheduledCount: scheduledCount,
      cancelledCount: cancelledCount,
      skippedCount: skippedCount,
      inexactFallbackScheduleKeys: List<String>.unmodifiable(fallbacks),
    );
  }

  tz.Location _resolveLocation(String timeZone) {
    final normalized = timeZone.trim();
    if (normalized.isNotEmpty) {
      try {
        return tz.getLocation(normalized);
      } catch (_) {
        // Fall through to UTC. A scheduler must never guess a health reminder
        // timezone from locale or network state.
      }
    }
    return tz.UTC;
  }
}
