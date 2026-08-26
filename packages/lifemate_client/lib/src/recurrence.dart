enum RecurrenceUnit { hour, day, week, month, year }

/// Versioned, product-facing recurrence rule shared by WellMate/CareMate.
///
/// Callers always request a finite window. [maxOccurrences] bounds a series
/// when the user chooses "after N occurrences"; raw cron expressions are not
/// persisted. Hourly rules are timestamp-based while day/week/month/year rules
/// preserve the anchor's local clock time.
class RecurrenceRule {
  const RecurrenceRule({
    this.version = 2,
    this.enabled = false,
    this.unit = RecurrenceUnit.month,
    this.interval = 1,
    this.weekdays = const <int>{},
    this.endDate,
    this.maxOccurrences,
  }) : assert(version > 0),
       assert(interval > 0),
       assert(maxOccurrences == null || maxOccurrences > 0);

  const RecurrenceRule.none()
    : version = 2,
      enabled = false,
      unit = RecurrenceUnit.month,
      interval = 1,
      weekdays = const <int>{},
      endDate = null,
      maxOccurrences = null;

  final int version;
  final bool enabled;
  final RecurrenceUnit unit;
  final int interval;
  final Set<int> weekdays;

  /// Inclusive local end boundary. Date-only values remain compatible with
  /// older persisted rules; timestamp values are supported for hourly series.
  final DateTime? endDate;

  /// Maximum number of occurrences in the whole series, counted from the
  /// series anchor rather than merely inside a queried window.
  final int? maxOccurrences;

  bool get isSubDaily => enabled && unit == RecurrenceUnit.hour;

  /// Resolves a count bound into an inclusive local timestamp/date boundary.
  /// If both explicit end and count are present, the earlier boundary wins.
  DateTime? persistenceEndDate(DateTime startDate) {
    final explicit = endDate;
    final count = maxOccurrences;
    if (!enabled || count == null) return explicit;
    final counted = _occurrenceAt(startDate, count);
    if (explicit == null || counted.isBefore(explicit)) return counted;
    return explicit;
  }

  DateTime _occurrenceAt(DateTime start, int ordinal) {
    final offset = ordinal - 1;
    switch (unit) {
      case RecurrenceUnit.hour:
        return start.add(Duration(hours: interval * offset));
      case RecurrenceUnit.day:
        return start.add(Duration(days: interval * offset));
      case RecurrenceUnit.month:
        return _addMonthsClamped(start, interval * offset);
      case RecurrenceUnit.year:
        return _addMonthsClamped(start, interval * offset * 12);
      case RecurrenceUnit.week:
        final allowed = weekdays.isEmpty ? <int>{start.weekday} : weekdays;
        var emitted = 0;
        var cursor = start;
        final guardLimit = (ordinal * interval * 7) + 14;
        for (var guard = 0; guard <= guardLimit; guard += 1) {
          final daysFromStart = _dayDistance(start, cursor);
          final weekIndex = daysFromStart ~/ 7;
          if (weekIndex % interval == 0 && allowed.contains(cursor.weekday)) {
            emitted += 1;
            if (emitted == ordinal) return cursor;
          }
          cursor = cursor.add(const Duration(days: 1));
        }
        throw StateError('Could not resolve recurrence count boundary.');
    }
  }

  Map<String, dynamic> toJson() => {
    'version': version,
    'enabled': enabled,
    if (enabled) 'unit': unit.name,
    if (enabled) 'interval': interval,
    if (enabled && weekdays.isNotEmpty) 'weekdays': weekdays.toList()..sort(),
    if (enabled && endDate != null)
      'endDate': isSubDaily ? endDate!.toIso8601String() : _date(endDate!),
    if (enabled && maxOccurrences != null) 'maxOccurrences': maxOccurrences,
  };

  factory RecurrenceRule.fromJson(dynamic value) {
    if (value is! Map || value['enabled'] != true) {
      return const RecurrenceRule.none();
    }
    final record = Map<String, dynamic>.from(value);
    final unit = RecurrenceUnit.values.firstWhere(
      (item) => item.name == record['unit']?.toString().toLowerCase(),
      orElse: () => RecurrenceUnit.month,
    );
    final interval = int.tryParse(record['interval']?.toString() ?? '') ?? 1;
    final version = int.tryParse(record['version']?.toString() ?? '') ?? 1;
    final rawMax = int.tryParse(record['maxOccurrences']?.toString() ?? '');
    final weekdays =
        (record['weekdays'] is List
                ? record['weekdays'] as List
                : const <dynamic>[])
            .map((item) => int.tryParse(item.toString()))
            .whereType<int>()
            .where((day) => day >= DateTime.monday && day <= DateTime.sunday)
            .toSet();
    return RecurrenceRule(
      version: version.clamp(1, 1000),
      enabled: true,
      unit: unit,
      interval: interval.clamp(1, unit == RecurrenceUnit.hour ? 8760 : 365),
      weekdays: weekdays,
      endDate: DateTime.tryParse(record['endDate']?.toString() ?? ''),
      maxOccurrences: rawMax == null ? null : rawMax.clamp(1, 10000),
    );
  }

  List<DateTime> occurrencesBetween({
    required DateTime startDate,
    required DateTime fromDate,
    required DateTime toDate,
  }) {
    final start = startDate;
    final from = fromDate;
    final to = toDate;
    if (to.isBefore(from) || to.isBefore(start)) return const [];
    final explicitEnd = endDate;
    final upper = explicitEnd == null || explicitEnd.isAfter(to)
        ? to
        : explicitEnd;
    if (upper.isBefore(start)) return const [];
    if (!enabled) {
      return !start.isBefore(from) && !start.isAfter(upper)
          ? [start]
          : const [];
    }

    final values = <DateTime>{};
    final limit = maxOccurrences;
    var emitted = 0;

    bool accept(DateTime cursor) {
      if (limit != null && emitted >= limit) return false;
      emitted += 1;
      if (!cursor.isBefore(from) && !cursor.isAfter(upper)) {
        values.add(cursor);
      }
      return limit == null || emitted < limit;
    }

    switch (unit) {
      case RecurrenceUnit.hour:
        for (
          var cursor = start;
          !cursor.isAfter(upper);
          cursor = cursor.add(Duration(hours: interval))
        ) {
          if (!accept(cursor)) break;
        }
      case RecurrenceUnit.day:
        for (
          var cursor = start;
          !cursor.isAfter(upper);
          cursor = cursor.add(Duration(days: interval))
        ) {
          if (!accept(cursor)) break;
        }
      case RecurrenceUnit.week:
        final allowed = weekdays.isEmpty ? <int>{start.weekday} : weekdays;
        for (
          var cursor = start;
          !cursor.isAfter(upper);
          cursor = cursor.add(const Duration(days: 1))
        ) {
          final daysFromStart = _dayDistance(start, cursor);
          final weekIndex = daysFromStart ~/ 7;
          if (weekIndex % interval == 0 && allowed.contains(cursor.weekday)) {
            if (!accept(cursor)) break;
          }
        }
      case RecurrenceUnit.month:
        for (var occurrence = 0; occurrence < 2400; occurrence++) {
          final cursor = _addMonthsClamped(start, occurrence * interval);
          if (cursor.isAfter(upper)) break;
          if (!accept(cursor)) break;
        }
      case RecurrenceUnit.year:
        for (var occurrence = 0; occurrence < 400; occurrence++) {
          final cursor = _addMonthsClamped(start, occurrence * interval * 12);
          if (cursor.isAfter(upper)) break;
          if (!accept(cursor)) break;
        }
    }
    final sorted = values.toList()..sort();
    return List<DateTime>.unmodifiable(sorted);
  }

  static int _dayDistance(DateTime start, DateTime cursor) =>
      DateTime(cursor.year, cursor.month, cursor.day)
          .difference(DateTime(start.year, start.month, start.day))
          .inDays;

  static DateTime _addMonthsClamped(DateTime start, int months) {
    final first = DateTime(start.year, start.month + months, 1);
    final lastDay = DateTime(first.year, first.month + 1, 0).day;
    return DateTime(
      first.year,
      first.month,
      start.day.clamp(1, lastDay),
      start.hour,
      start.minute,
      start.second,
      start.millisecond,
      start.microsecond,
    );
  }

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
