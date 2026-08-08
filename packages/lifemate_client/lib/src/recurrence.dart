enum RecurrenceUnit { day, week, month, year }

class RecurrenceRule {
  const RecurrenceRule({
    this.enabled = false,
    this.unit = RecurrenceUnit.month,
    this.interval = 1,
    this.weekdays = const <int>{},
    this.endDate,
  }) : assert(interval > 0);

  const RecurrenceRule.none()
    : enabled = false,
      unit = RecurrenceUnit.month,
      interval = 1,
      weekdays = const <int>{},
      endDate = null;

  final bool enabled;
  final RecurrenceUnit unit;
  final int interval;
  final Set<int> weekdays;
  final DateTime? endDate;

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    if (enabled) 'unit': unit.name,
    if (enabled) 'interval': interval,
    if (enabled && weekdays.isNotEmpty) 'weekdays': weekdays.toList()..sort(),
    if (enabled && endDate != null) 'endDate': _date(endDate!),
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
    final weekdays =
        (record['weekdays'] is List
                ? record['weekdays'] as List
                : const <dynamic>[])
            .map((item) => int.tryParse(item.toString()))
            .whereType<int>()
            .where((day) => day >= DateTime.monday && day <= DateTime.sunday)
            .toSet();
    return RecurrenceRule(
      enabled: true,
      unit: unit,
      interval: interval.clamp(1, 365),
      weekdays: weekdays,
      endDate: DateTime.tryParse(record['endDate']?.toString() ?? ''),
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
    switch (unit) {
      case RecurrenceUnit.day:
        for (
          var cursor = start;
          !cursor.isAfter(upper);
          cursor = cursor.add(Duration(days: interval))
        ) {
          if (!cursor.isBefore(from)) values.add(cursor);
        }
      case RecurrenceUnit.week:
        final allowed = weekdays.isEmpty ? <int>{start.weekday} : weekdays;
        final first = from.isAfter(start) ? from : start;
        for (
          var cursor = first;
          !cursor.isAfter(upper);
          cursor = cursor.add(const Duration(days: 1))
        ) {
          final daysFromStart = cursor.difference(start).inDays;
          final weekIndex = daysFromStart ~/ 7;
          if (weekIndex % interval == 0 && allowed.contains(cursor.weekday)) {
            values.add(cursor);
          }
        }
      case RecurrenceUnit.month:
        for (var occurrence = 0; occurrence < 2400; occurrence++) {
          final cursor = _addMonthsClamped(start, occurrence * interval);
          if (cursor.isAfter(upper)) break;
          if (!cursor.isBefore(from)) values.add(cursor);
        }
      case RecurrenceUnit.year:
        for (var occurrence = 0; occurrence < 400; occurrence++) {
          final cursor = _addMonthsClamped(start, occurrence * interval * 12);
          if (cursor.isAfter(upper)) break;
          if (!cursor.isBefore(from)) values.add(cursor);
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
