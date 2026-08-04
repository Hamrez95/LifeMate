class WomenCalendarEstimate {
  const WomenCalendarEstimate({
    required this.cycleStart,
    required this.today,
    required this.cycleDay,
    required this.cycleLength,
    required this.periodLength,
    required this.estimatedBleeding,
    required this.phase,
    required this.nextPeriodStart,
    required this.daysUntilNextPeriod,
  });

  final DateTime cycleStart;
  final DateTime today;
  final int cycleDay;
  final int cycleLength;
  final int periodLength;
  final bool estimatedBleeding;
  final WomenCalendarPhase phase;
  final DateTime nextPeriodStart;
  final int daysUntilNextPeriod;

  static WomenCalendarEstimate calculate({
    required DateTime lastPeriodStart,
    required int cycleLength,
    required int periodLength,
    DateTime? today,
  }) {
    if (cycleLength < 21 || cycleLength > 45) {
      throw ArgumentError.value(cycleLength, 'cycleLength');
    }
    if (periodLength < 1 || periodLength > 10 || periodLength >= cycleLength) {
      throw ArgumentError.value(periodLength, 'periodLength');
    }
    final start = _dateOnly(lastPeriodStart);
    final current = _dateOnly(today ?? DateTime.now());
    final rawDifference = current.difference(start).inDays;
    final cyclesElapsed = rawDifference < 0 ? 0 : rawDifference ~/ cycleLength;
    var cycleStart = start.add(Duration(days: cyclesElapsed * cycleLength));
    if (cycleStart.isAfter(current)) cycleStart = start;
    final cycleDay = current.difference(cycleStart).inDays + 1;
    final nextPeriodStart = cycleStart.add(Duration(days: cycleLength));
    final daysUntilNextPeriod = nextPeriodStart
        .difference(current)
        .inDays
        .clamp(0, cycleLength);
    final estimatedBleeding = cycleDay <= periodLength;
    final phase = estimatedBleeding
        ? WomenCalendarPhase.period
        : cycleDay <= periodLength + 4
        ? WomenCalendarPhase.postPeriod
        : daysUntilNextPeriod <= 5
        ? WomenCalendarPhase.prePeriod
        : WomenCalendarPhase.cycle;
    return WomenCalendarEstimate(
      cycleStart: cycleStart,
      today: current,
      cycleDay: cycleDay,
      cycleLength: cycleLength,
      periodLength: periodLength,
      estimatedBleeding: estimatedBleeding,
      phase: phase,
      nextPeriodStart: nextPeriodStart,
      daysUntilNextPeriod: daysUntilNextPeriod,
    );
  }

  bool isEstimatedPeriodDay(DateTime value) {
    final date = _dateOnly(value);
    final difference = date.difference(cycleStart).inDays;
    if (difference < 0) return false;
    final day = (difference % cycleLength) + 1;
    return day <= periodLength;
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}

enum WomenCalendarPhase { period, postPeriod, cycle, prePeriod }
