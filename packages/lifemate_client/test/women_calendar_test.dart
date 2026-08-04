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
    expect(estimate.estimatedBleeding, isTrue);
    expect(estimate.nextPeriodStart, DateTime(2026, 8, 29));
    expect(estimate.daysUntilNextPeriod, 25);
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
    expect(estimate.daysUntilNextPeriod, 4);
    expect(estimate.isEstimatedPeriodDay(DateTime(2026, 8, 24)), isTrue);
  });
}
