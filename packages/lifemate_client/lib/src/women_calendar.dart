class WomenCalendarEstimate {
  const WomenCalendarEstimate({
    required this.cycleStart,
    required this.today,
    required this.cycleDay,
    required this.cycleLength,
    required this.periodLength,
    required this.estimatedBleeding,
    required this.phase,
    required this.detailedPhase,
    required this.ovulationDay,
    required this.fertileWindowStartDay,
    required this.fertileWindowEndDay,
    required this.pmsStartDay,
    required this.nextPeriodStart,
    required this.daysUntilNextPeriod,
  });

  final DateTime cycleStart;
  final DateTime today;
  final int cycleDay;
  final int cycleLength;
  final int periodLength;
  final bool estimatedBleeding;

  /// Compatibility summary retained for existing consumers.
  final WomenCalendarPhase phase;

  /// The richer wellness phase used by the women calendar UI.
  final WomenCyclePhase detailedPhase;
  final int ovulationDay;
  final int fertileWindowStartDay;
  final int fertileWindowEndDay;
  final int pmsStartDay;
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

    final ovulationDay = (cycleLength - 14).clamp(
      periodLength + 2,
      cycleLength - 5,
    );
    final fertileWindowStartDay = (ovulationDay - 5).clamp(
      periodLength + 1,
      ovulationDay,
    );
    final fertileWindowEndDay = (ovulationDay + 1).clamp(
      ovulationDay,
      cycleLength,
    );
    final pmsStartDay = (cycleLength - 4).clamp(
      fertileWindowEndDay + 1,
      cycleLength,
    );

    final detailedPhase = _phaseForCycleDay(
      cycleDay: cycleDay,
      periodLength: periodLength,
      ovulationDay: ovulationDay,
      fertileWindowStartDay: fertileWindowStartDay,
      fertileWindowEndDay: fertileWindowEndDay,
      pmsStartDay: pmsStartDay,
    );
    final phase = switch (detailedPhase) {
      WomenCyclePhase.period => WomenCalendarPhase.period,
      WomenCyclePhase.follicular => WomenCalendarPhase.postPeriod,
      WomenCyclePhase.fertile ||
      WomenCyclePhase.ovulation ||
      WomenCyclePhase.luteal => WomenCalendarPhase.cycle,
      WomenCyclePhase.pms => WomenCalendarPhase.prePeriod,
    };

    return WomenCalendarEstimate(
      cycleStart: cycleStart,
      today: current,
      cycleDay: cycleDay,
      cycleLength: cycleLength,
      periodLength: periodLength,
      estimatedBleeding: detailedPhase == WomenCyclePhase.period,
      phase: phase,
      detailedPhase: detailedPhase,
      ovulationDay: ovulationDay,
      fertileWindowStartDay: fertileWindowStartDay,
      fertileWindowEndDay: fertileWindowEndDay,
      pmsStartDay: pmsStartDay,
      nextPeriodStart: nextPeriodStart,
      daysUntilNextPeriod: daysUntilNextPeriod,
    );
  }

  int cycleDayForDate(DateTime value) {
    final difference = _dateOnly(value).difference(cycleStart).inDays;
    return _positiveModulo(difference, cycleLength) + 1;
  }

  WomenCyclePhase phaseForDate(DateTime value) {
    return _phaseForCycleDay(
      cycleDay: cycleDayForDate(value),
      periodLength: periodLength,
      ovulationDay: ovulationDay,
      fertileWindowStartDay: fertileWindowStartDay,
      fertileWindowEndDay: fertileWindowEndDay,
      pmsStartDay: pmsStartDay,
    );
  }

  bool isEstimatedPeriodDay(DateTime value) =>
      phaseForDate(value) == WomenCyclePhase.period;

  bool isEstimatedFertileDay(DateTime value) {
    final phase = phaseForDate(value);
    return phase == WomenCyclePhase.fertile ||
        phase == WomenCyclePhase.ovulation;
  }

  bool isEstimatedOvulationDay(DateTime value) =>
      phaseForDate(value) == WomenCyclePhase.ovulation;

  bool isEstimatedPmsDay(DateTime value) =>
      phaseForDate(value) == WomenCyclePhase.pms;

  static WomenCyclePhase _phaseForCycleDay({
    required int cycleDay,
    required int periodLength,
    required int ovulationDay,
    required int fertileWindowStartDay,
    required int fertileWindowEndDay,
    required int pmsStartDay,
  }) {
    if (cycleDay <= periodLength) return WomenCyclePhase.period;
    if (cycleDay < fertileWindowStartDay) return WomenCyclePhase.follicular;
    if (cycleDay == ovulationDay) return WomenCyclePhase.ovulation;
    if (cycleDay <= fertileWindowEndDay) return WomenCyclePhase.fertile;
    if (cycleDay >= pmsStartDay) return WomenCyclePhase.pms;
    return WomenCyclePhase.luteal;
  }

  static int _positiveModulo(int value, int divisor) =>
      ((value % divisor) + divisor) % divisor;

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}

/// Compatibility phase used by older clients.
enum WomenCalendarPhase { period, postPeriod, cycle, prePeriod }

/// Estimated wellness phases. They are not a medical diagnosis and must not be
/// used as contraception or as proof of ovulation.
enum WomenCyclePhase { period, follicular, fertile, ovulation, luteal, pms }
