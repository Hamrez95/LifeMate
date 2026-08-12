import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test(
    'keeps period timing deterministic without claiming fertility certainty',
    () {
      final estimate = WomenCalendarEstimate.calculate(
        lastPeriodStart: DateTime(2026, 8, 1),
        cycleLength: 28,
        periodLength: 5,
        today: DateTime(2026, 8, 4),
      );

      expect(estimate.cycleDay, 4);
      expect(estimate.phase, WomenCalendarPhase.period);
      expect(estimate.detailedPhase, WomenCyclePhase.period);
      expect(estimate.estimatedBleeding, isTrue);
      expect(estimate.nextPeriodStart, DateTime(2026, 8, 29));
      expect(estimate.daysUntilNextPeriod, 25);
      expect(estimate.confidence, WomenCycleEstimateConfidence.low);
      expect(estimate.fertilityEstimateReliable, isFalse);
    },
  );

  test('settings alone never expose fertile or ovulation helpers', () {
    final estimate = WomenCalendarEstimate.calculate(
      lastPeriodStart: DateTime(2026, 8, 1),
      cycleLength: 28,
      periodLength: 5,
      today: DateTime(2026, 8, 1),
    );

    expect(estimate.ovulationDay, 14);
    expect(estimate.fertileWindowStartDay, 9);
    expect(estimate.fertileWindowEndDay, 15);
    expect(estimate.fertilityEstimateReliable, isFalse);
    expect(estimate.isEstimatedFertileDay(DateTime(2026, 8, 10)), isFalse);
    expect(estimate.isEstimatedOvulationDay(DateTime(2026, 8, 14)), isFalse);
  });

  test('repeated stable period starts enable a high-confidence estimate', () {
    final estimate = WomenCalendarEstimate.calculateFromEpisodes(
      lastPeriodStart: DateTime(2026, 7, 24),
      configuredCycleLength: 28,
      periodLength: 5,
      periodStarts: [
        DateTime(2026, 5, 1),
        DateTime(2026, 5, 29),
        DateTime(2026, 6, 26),
        DateTime(2026, 7, 24),
      ],
      today: DateTime(2026, 7, 24),
    );

    expect(estimate.pattern, WomenCyclePattern.regular);
    expect(estimate.confidence, WomenCycleEstimateConfidence.high);
    expect(estimate.fertilityEstimateReliable, isTrue);
    expect(estimate.isEstimatedFertileDay(DateTime(2026, 8, 2)), isTrue);
    expect(estimate.isEstimatedOvulationDay(DateTime(2026, 8, 6)), isTrue);
  });

  test(
    'variable history suppresses fertility timing while preserving cycle use',
    () {
      final estimate = WomenCalendarEstimate.calculateFromEpisodes(
        lastPeriodStart: DateTime(2026, 7, 26),
        configuredCycleLength: 28,
        periodLength: 5,
        periodStarts: [
          DateTime(2026, 5, 1),
          DateTime(2026, 5, 25),
          DateTime(2026, 6, 27),
          DateTime(2026, 7, 26),
        ],
        today: DateTime(2026, 7, 26),
      );

      expect(estimate.pattern, WomenCyclePattern.variable);
      expect(estimate.confidence, WomenCycleEstimateConfidence.low);
      expect(estimate.fertilityEstimateReliable, isFalse);
      expect(estimate.isEstimatedFertileDay(DateTime(2026, 8, 5)), isFalse);
    },
  );

  test('insufficient history remains low-confidence', () {
    final estimate = WomenCalendarEstimate.calculateFromEpisodes(
      lastPeriodStart: DateTime(2026, 8, 1),
      configuredCycleLength: 30,
      periodLength: 6,
      periodStarts: [DateTime(2026, 8, 1)],
      today: DateTime(2026, 8, 1),
    );

    expect(estimate.pattern, WomenCyclePattern.insufficientData);
    expect(estimate.confidence, WomenCycleEstimateConfidence.low);
    expect(estimate.cycleLength, 30);
    expect(estimate.fertilityEstimateReliable, isFalse);
  });

  test(
    'period and PMS helpers remain available without fertility confidence',
    () {
      final estimate = WomenCalendarEstimate.calculate(
        lastPeriodStart: DateTime(2026, 8, 1),
        cycleLength: 30,
        periodLength: 6,
        today: DateTime(2026, 8, 1),
      );

      final nextCycleStart = DateTime(2026, 8, 31);
      expect(estimate.cycleDayForDate(nextCycleStart), 1);
      expect(estimate.isEstimatedPeriodDay(nextCycleStart), isTrue);
      expect(estimate.isEstimatedFertileDay(DateTime(2026, 8, 16)), isFalse);
      expect(estimate.isEstimatedOvulationDay(DateTime(2026, 8, 16)), isFalse);
      expect(estimate.isEstimatedPmsDay(DateTime(2026, 8, 27)), isTrue);
    },
  );

  test('latest configured period start participates in confidence history', () {
    final estimate = WomenCalendarEstimate.calculateFromEpisodes(
      lastPeriodStart: DateTime(2026, 8, 1),
      configuredCycleLength: 28,
      periodLength: 5,
      periodStarts: [
        DateTime(2026, 5, 1),
        DateTime(2026, 5, 29),
        DateTime(2026, 6, 26),
      ],
      today: DateTime(2026, 8, 1),
    );

    expect(estimate.pattern, WomenCyclePattern.variable);
    expect(estimate.confidence, WomenCycleEstimateConfidence.low);
    expect(estimate.fertilityEstimateReliable, isFalse);
  });

  test(
    'low confidence does not reveal the ovulation boundary via luteal phase',
    () {
      final estimate = WomenCalendarEstimate.calculate(
        lastPeriodStart: DateTime(2026, 8, 1),
        cycleLength: 28,
        periodLength: 5,
        today: DateTime(2026, 8, 16),
      );

      expect(estimate.fertilityEstimateReliable, isFalse);
      expect(estimate.detailedPhase, WomenCyclePhase.follicular);
      expect(
        estimate.phaseForDate(DateTime(2026, 8, 16)),
        WomenCyclePhase.follicular,
      );
    },
  );

  test(
    'normalizes episode gaps by calendar date rather than elapsed local hours',
    () {
      final assessment = WomenCycleHistoryAssessment.fromPeriodStarts(
        periodStarts: [
          DateTime(2026, 2, 22, 23, 30),
          DateTime(2026, 3, 15, 0, 15),
          DateTime(2026, 4, 5, 18),
        ],
        fallbackCycleLength: 21,
      );

      expect(assessment.pattern, WomenCyclePattern.regular);
      expect(assessment.representativeCycleLength, 21);
    },
  );
}
