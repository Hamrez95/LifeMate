import 'dart:math' as math;

class WomenCycleHistoryAssessment {
  const WomenCycleHistoryAssessment({
    required this.sampleCount,
    required this.intervalCount,
    required this.pattern,
    required this.confidence,
    required this.representativeCycleLength,
    required this.minimumObservedCycleLength,
    required this.maximumObservedCycleLength,
  });

  final int sampleCount;
  final int intervalCount;
  final WomenCyclePattern pattern;
  final WomenCycleEstimateConfidence confidence;
  final int representativeCycleLength;
  final int? minimumObservedCycleLength;
  final int? maximumObservedCycleLength;

  bool get fertilityEstimateReliable =>
      pattern == WomenCyclePattern.regular &&
      confidence != WomenCycleEstimateConfidence.low;

  static WomenCycleHistoryAssessment fromPeriodStarts({
    required Iterable<DateTime> periodStarts,
    required int fallbackCycleLength,
  }) {
    final normalized =
        periodStarts
            .map((value) => DateTime.utc(value.year, value.month, value.day))
            .toSet()
            .toList()
          ..sort();
    final intervals = <int>[];
    for (var index = 1; index < normalized.length; index++) {
      final days = normalized[index].difference(normalized[index - 1]).inDays;
      if (days >= 15 && days <= 90) intervals.add(days);
    }
    final usable = intervals
        .where((value) => value >= 21 && value <= 45)
        .toList();
    final representative = usable.isEmpty
        ? fallbackCycleLength.clamp(21, 45)
        : _median(usable);

    if (intervals.length < 2) {
      return WomenCycleHistoryAssessment(
        sampleCount: normalized.length,
        intervalCount: intervals.length,
        pattern: WomenCyclePattern.insufficientData,
        confidence: WomenCycleEstimateConfidence.low,
        representativeCycleLength: representative,
        minimumObservedCycleLength: intervals.isEmpty
            ? null
            : intervals.reduce(math.min),
        maximumObservedCycleLength: intervals.isEmpty
            ? null
            : intervals.reduce(math.max),
      );
    }

    final minimum = intervals.reduce(math.min);
    final maximum = intervals.reduce(math.max);
    final spread = maximum - minimum;
    final variable =
        spread > 7 || intervals.any((value) => value < 21 || value > 45);
    if (variable) {
      return WomenCycleHistoryAssessment(
        sampleCount: normalized.length,
        intervalCount: intervals.length,
        pattern: WomenCyclePattern.variable,
        confidence: WomenCycleEstimateConfidence.low,
        representativeCycleLength: representative,
        minimumObservedCycleLength: minimum,
        maximumObservedCycleLength: maximum,
      );
    }

    return WomenCycleHistoryAssessment(
      sampleCount: normalized.length,
      intervalCount: intervals.length,
      pattern: WomenCyclePattern.regular,
      confidence: intervals.length >= 3 && spread <= 4
          ? WomenCycleEstimateConfidence.high
          : WomenCycleEstimateConfidence.medium,
      representativeCycleLength: representative,
      minimumObservedCycleLength: minimum,
      maximumObservedCycleLength: maximum,
    );
  }

  static int _median(List<int> values) {
    final sorted = [...values]..sort();
    final middle = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[middle];
    return ((sorted[middle - 1] + sorted[middle]) / 2).round();
  }
}

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
    this.historyAssessment,
  });

  final DateTime cycleStart;
  final DateTime today;
  final int cycleDay;
  final int cycleLength;
  final int periodLength;
  final bool estimatedBleeding;
  final WomenCalendarPhase phase;
  final WomenCyclePhase detailedPhase;
  final int ovulationDay;
  final int fertileWindowStartDay;
  final int fertileWindowEndDay;
  final int pmsStartDay;
  final DateTime nextPeriodStart;
  final int daysUntilNextPeriod;
  final WomenCycleHistoryAssessment? historyAssessment;

  WomenCycleEstimateConfidence get confidence =>
      historyAssessment?.confidence ?? WomenCycleEstimateConfidence.low;
  WomenCyclePattern get pattern =>
      historyAssessment?.pattern ?? WomenCyclePattern.insufficientData;
  bool get fertilityEstimateReliable =>
      historyAssessment?.fertilityEstimateReliable ?? false;

  static WomenCalendarEstimate calculate({
    required DateTime lastPeriodStart,
    required int cycleLength,
    required int periodLength,
    DateTime? today,
    WomenCycleHistoryAssessment? historyAssessment,
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

    final fertilityReliable =
        historyAssessment?.fertilityEstimateReliable ?? false;
    final detailedPhase = _phaseForCycleDay(
      cycleDay: cycleDay,
      periodLength: periodLength,
      ovulationDay: ovulationDay,
      fertileWindowStartDay: fertileWindowStartDay,
      fertileWindowEndDay: fertileWindowEndDay,
      pmsStartDay: pmsStartDay,
      fertilityReliable: fertilityReliable,
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
      historyAssessment: historyAssessment,
    );
  }

  static WomenCalendarEstimate calculateFromEpisodes({
    required DateTime lastPeriodStart,
    required int configuredCycleLength,
    required int periodLength,
    required Iterable<DateTime> periodStarts,
    DateTime? today,
  }) {
    final history = WomenCycleHistoryAssessment.fromPeriodStarts(
      periodStarts: [...periodStarts, lastPeriodStart],
      fallbackCycleLength: configuredCycleLength,
    );
    return calculate(
      lastPeriodStart: lastPeriodStart,
      cycleLength: history.representativeCycleLength,
      periodLength: periodLength,
      today: today,
      historyAssessment: history,
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
      fertilityReliable: fertilityEstimateReliable,
    );
  }

  bool isEstimatedPeriodDay(DateTime value) =>
      phaseForDate(value) == WomenCyclePhase.period;

  bool isEstimatedFertileDay(DateTime value) {
    if (!fertilityEstimateReliable) return false;
    final phase = phaseForDate(value);
    return phase == WomenCyclePhase.fertile ||
        phase == WomenCyclePhase.ovulation;
  }

  bool isEstimatedOvulationDay(DateTime value) =>
      fertilityEstimateReliable &&
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
    required bool fertilityReliable,
  }) {
    if (cycleDay <= periodLength) return WomenCyclePhase.period;
    if (!fertilityReliable) {
      if (cycleDay >= pmsStartDay) return WomenCyclePhase.pms;
      return WomenCyclePhase.follicular;
    }
    if (cycleDay == ovulationDay) return WomenCyclePhase.ovulation;
    if (cycleDay >= fertileWindowStartDay && cycleDay <= fertileWindowEndDay) {
      return WomenCyclePhase.fertile;
    }
    if (cycleDay >= pmsStartDay) return WomenCyclePhase.pms;
    if (cycleDay > fertileWindowEndDay) return WomenCyclePhase.luteal;
    return WomenCyclePhase.follicular;
  }

  static int _positiveModulo(int value, int divisor) =>
      ((value % divisor) + divisor) % divisor;

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}

enum WomenCalendarPhase { period, postPeriod, cycle, prePeriod }

enum WomenCyclePhase { period, follicular, fertile, ovulation, luteal, pms }

enum WomenCycleEstimateConfidence { low, medium, high }

enum WomenCyclePattern { insufficientData, regular, variable }
