import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test('calculates deterministic cycle day and next period estimate', () {
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
  });

  test('maps the complete estimated wellness cycle deterministically', () {
    final estimate = WomenCalendarEstimate.calculate(
      lastPeriodStart: DateTime(2026, 8, 1),
      cycleLength: 28,
      periodLength: 5,
      today: DateTime(2026, 8, 1),
    );

    expect(estimate.ovulationDay, 14);
    expect(estimate.fertileWindowStartDay, 9);
    expect(estimate.fertileWindowEndDay, 15);
    expect(estimate.pmsStartDay, 24);

    expect(estimate.phaseForDate(DateTime(2026, 8, 3)), WomenCyclePhase.period);
    expect(
      estimate.phaseForDate(DateTime(2026, 8, 7)),
      WomenCyclePhase.follicular,
    );
    expect(
      estimate.phaseForDate(DateTime(2026, 8, 10)),
      WomenCyclePhase.fertile,
    );
    expect(
      estimate.phaseForDate(DateTime(2026, 8, 14)),
      WomenCyclePhase.ovulation,
    );
    expect(
      estimate.phaseForDate(DateTime(2026, 8, 18)),
      WomenCyclePhase.luteal,
    );
    expect(estimate.phaseForDate(DateTime(2026, 8, 24)), WomenCyclePhase.pms);
  });

  test('supports irregular user settings inside the bounded MVP range', () {
    final estimate = WomenCalendarEstimate.calculate(
      lastPeriodStart: DateTime(2026, 7, 20),
      cycleLength: 35,
      periodLength: 7,
      today: DateTime(2026, 8, 20),
    );

    expect(estimate.cycleDay, 32);
    expect(estimate.phase, WomenCalendarPhase.prePeriod);
    expect(estimate.detailedPhase, WomenCyclePhase.pms);
    expect(estimate.daysUntilNextPeriod, 4);
    expect(estimate.isEstimatedPeriodDay(DateTime(2026, 8, 24)), isTrue);
  });

  test('classifies dates across repeated cycles and exposes helpers', () {
    final estimate = WomenCalendarEstimate.calculate(
      lastPeriodStart: DateTime(2026, 8, 1),
      cycleLength: 30,
      periodLength: 6,
      today: DateTime(2026, 8, 1),
    );

    final nextCycleStart = DateTime(2026, 8, 31);
    expect(estimate.cycleDayForDate(nextCycleStart), 1);
    expect(estimate.isEstimatedPeriodDay(nextCycleStart), isTrue);
    expect(estimate.isEstimatedFertileDay(DateTime(2026, 8, 16)), isTrue);
    expect(estimate.isEstimatedOvulationDay(DateTime(2026, 8, 16)), isTrue);
    expect(estimate.isEstimatedPmsDay(DateTime(2026, 8, 27)), isTrue);
  });
}
