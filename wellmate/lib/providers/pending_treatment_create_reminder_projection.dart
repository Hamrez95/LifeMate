import 'package:lifemate_core/lifemate_reminders.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// A bounded local-only reminder occurrence derived from a pending durable
/// treatment-create mutation.
///
/// The identity is intentionally opaque and must never be used as a server
/// treatment/dose occurrence ID or for adherence actions.
final class PendingTreatmentCreateReminderProjection {
  const PendingTreatmentCreateReminderProjection({
    required this.sourceOccurrenceKey,
    required this.sourceRevision,
    required this.triggerUtc,
  });

  final String sourceOccurrenceKey;
  final int sourceRevision;
  final DateTime triggerUtc;
}

List<PendingTreatmentCreateReminderProjection>
projectPendingTreatmentCreateReminders({
  required Iterable<Map<String, dynamic>> pendingCreates,
  required DateTime nowUtc,
  Duration horizon = const Duration(days: 45),
}) {
  if (horizon <= Duration.zero) {
    throw ArgumentError.value(horizon, 'horizon');
  }

  tz_data.initializeTimeZones();
  final normalizedNow = nowUtc.toUtc();
  final horizonEnd = normalizedNow.add(horizon);
  final result = <PendingTreatmentCreateReminderProjection>[];
  final seen = <String>{};

  for (final raw in pendingCreates) {
    if (raw['pendingSync'] != true) continue;

    final requestId = raw['clientRequestId']?.toString().trim() ?? '';
    final startDate = _dateOnly(raw['startDate']);
    final endDate = raw['endDate'] == null ? null : _dateOnly(raw['endDate']);
    final recurrence = raw['recurrence'];
    final zoneName = raw['timeZone']?.toString().trim() ?? '';
    final lead = _boundedReminderLead(raw['patientReminderMinutesBefore']);

    if (requestId.isEmpty ||
        startDate == null ||
        (endDate != null && endDate.isBefore(startDate)) ||
        recurrence is! Map ||
        recurrence['enabled'] != false ||
        zoneName.isEmpty ||
        lead == null) {
      continue;
    }

    final location = _location(zoneName);
    if (location == null) continue;

    final schedules = _schedules(raw['schedules']);
    if (schedules == null || schedules.isEmpty) continue;

    final localNow = tz.TZDateTime.from(normalizedNow, location);
    final localHorizon = tz.TZDateTime.from(horizonEnd, location);
    final first = _maxDate(
      startDate,
      DateTime(localNow.year, localNow.month, localNow.day),
    );
    final localHorizonDate = DateTime(
      localHorizon.year,
      localHorizon.month,
      localHorizon.day,
    );
    final last = _minDate(endDate ?? localHorizonDate, localHorizonDate);
    if (last.isBefore(first)) continue;

    for (
      var date = first;
      !date.isAfter(last);
      date = date.add(const Duration(days: 1))
    ) {
      for (final schedule in schedules) {
        if (_weekdayName(date.weekday) != schedule.dayOfWeek) continue;

        final parts = schedule.localTime.split(':');
        final scheduledLocal = tz.TZDateTime(
          location,
          date.year,
          date.month,
          date.day,
          int.parse(parts[0]),
          int.parse(parts[1]),
        );
        final triggerUtc = scheduledLocal.toUtc().subtract(
          Duration(minutes: lead),
        );
        if (!triggerUtc.isAfter(normalizedNow) ||
            triggerUtc.isAfter(horizonEnd)) {
          continue;
        }

        final dateText = _dateText(date);
        final occurrenceIdentity =
            'pending-treatment-create-occurrence-v1|$requestId|$dateText|${schedule.localTime}';
        final opaqueOccurrence = LifeMateReminderIdentity.stableHash(
          occurrenceIdentity,
        );
        final sourceOccurrenceKey =
            'wellmate:pending-treatment-create:$opaqueOccurrence';
        if (!seen.add(sourceOccurrenceKey)) continue;

        final sourceRevision = LifeMateReminderIdentity.stableRevisionFor(
          'pending-treatment-create-reminder-v1|$occurrenceIdentity|$zoneName|lead:$lead',
        );
        result.add(
          PendingTreatmentCreateReminderProjection(
            sourceOccurrenceKey: sourceOccurrenceKey,
            sourceRevision: sourceRevision,
            triggerUtc: triggerUtc,
          ),
        );
      }
    }
  }

  result.sort((left, right) {
    final trigger = left.triggerUtc.compareTo(right.triggerUtc);
    return trigger != 0
        ? trigger
        : left.sourceOccurrenceKey.compareTo(right.sourceOccurrenceKey);
  });
  return List<PendingTreatmentCreateReminderProjection>.unmodifiable(result);
}

final class _PendingSchedule {
  const _PendingSchedule(this.dayOfWeek, this.localTime);

  final String dayOfWeek;
  final String localTime;
}

List<_PendingSchedule>? _schedules(Object? raw) {
  if (raw is! List || raw.isEmpty) return null;
  final result = <_PendingSchedule>[];
  final seen = <String>{};
  for (final item in raw) {
    if (item is! Map) return null;
    final day = item['dayOfWeek']?.toString().trim().toLowerCase() ?? '';
    final time = item['localTime']?.toString().trim() ?? '';
    if (!_weekdays.contains(day) || !_localTime.hasMatch(time)) return null;
    if (seen.add('$day|$time')) result.add(_PendingSchedule(day, time));
  }
  return result;
}

DateTime? _dateOnly(Object? value) {
  final text = value?.toString().trim() ?? '';
  if (!_localDate.hasMatch(text)) return null;
  final parsed = DateTime.tryParse(text);
  return parsed == null ? null : DateTime(parsed.year, parsed.month, parsed.day);
}

tz.Location? _location(String name) {
  try {
    return tz.getLocation(name);
  } catch (_) {
    return null;
  }
}

int? _boundedReminderLead(Object? value) {
  final parsed = value is int ? value : int.tryParse(value?.toString() ?? '');
  if (parsed == null || parsed < 0 || parsed > 10080) return null;
  return parsed;
}

DateTime _maxDate(DateTime left, DateTime right) =>
    left.isAfter(right) ? left : right;
DateTime _minDate(DateTime left, DateTime right) =>
    left.isBefore(right) ? left : right;

String _weekdayName(int weekday) => switch (weekday) {
  DateTime.monday => 'monday',
  DateTime.tuesday => 'tuesday',
  DateTime.wednesday => 'wednesday',
  DateTime.thursday => 'thursday',
  DateTime.friday => 'friday',
  DateTime.saturday => 'saturday',
  DateTime.sunday => 'sunday',
  _ => '',
};

String _dateText(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

final _localDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');
final _localTime = RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$');
const _weekdays = <String>{
  'monday',
  'tuesday',
  'wednesday',
  'thursday',
  'friday',
  'saturday',
  'sunday',
};
