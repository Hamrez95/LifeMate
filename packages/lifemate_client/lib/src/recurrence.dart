enum RecurrenceUnit { day, week, month, year }

/// Versioned, product-facing recurrence rule shared by WellMate/CareMate.
///
/// The rule is intentionally bounded: callers always ask for a finite date
/// window and [maxOccurrences] caps the generated series when the user chooses
/// "after N occurrences". No cron expression is persisted or evaluated here.
class RecurrenceRule {
  const RecurrenceRule({
    this.version = 1,
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
    : version = 1,
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
  final DateTime? endDate;

  /// Maximum number of occurrences in the whole series, counted from
  /// [startDate], not merely inside the queried window.
  final int? maxOccurrences;

  Map<String, dynamic> toJson() => {
    'version': version,
    'enabled': enabled,
    if (enabled) 'unit': unit.name,
    if (enabled) 'interval': interval,
    if (enabled && weekdays.isNotEmpty) 'weekdays': weekdays.toList()..sort(),
    if (enabled && endDate != null) 'endDate': _date(endDate!),
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
      interval: interval.clamp(1, 365),
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
    final start = _onlyDate(startDate);
    final from = _onlyDate(fromDate);
    final to = _onlyDate(toDate);
    if (to.isBefore(from) || to.isBefore(start)) return const [];
    final upper = endDate == null || _onlyDate(endDate!).isAfter(to)
        ? to
        : _onlyDate(endDate!);
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
        // Count from the series start, even when the requested window begins
        // later, so maxOccurrences means the same thing for every page/query.
        for (
          var cursor = start;
          !cursor.isAfter(upper);
          cursor = cursor.add(const Duration(days: 1))
        ) {
          final daysFromStart = cursor.difference(start).inDays;
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

  static DateTime _addMonthsClamped(DateTime start, int months) {
    final first = DateTime(start.year, start.month + months, 1);
    final lastDay = DateTime(first.year, first.month + 1, 0).day;
    return DateTime(first.year, first.month, start.day.clamp(1, lastDay));
  }

  static DateTime _onlyDate(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
