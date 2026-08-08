import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test(
    'visit recurrence every N months is deterministic and clamps month end',
    () {
      const rule = RecurrenceRule(
        enabled: true,
        unit: RecurrenceUnit.month,
        interval: 1,
      );
      final dates = rule.occurrencesBetween(
        startDate: DateTime(2026, 1, 31),
        fromDate: DateTime(2026, 1, 1),
        toDate: DateTime(2026, 4, 30),
      );
      expect(dates, [
        DateTime(2026, 1, 31),
        DateTime(2026, 2, 28),
        DateTime(2026, 3, 31),
        DateTime(2026, 4, 30),
      ]);
    },
  );

  test('injection recurrence supports every N months', () {
    const rule = RecurrenceRule(
      enabled: true,
      unit: RecurrenceUnit.month,
      interval: 6,
    );
    final dates = rule.occurrencesBetween(
      startDate: DateTime(2026, 8, 17),
      fromDate: DateTime(2026, 8, 1),
      toDate: DateTime(2027, 9, 1),
    );
    expect(dates, [
      DateTime(2026, 8, 17),
      DateTime(2027, 2, 17),
      DateTime(2027, 8, 17),
    ]);
  });

  test('weekly recurrence emits no duplicate dates', () {
    const rule = RecurrenceRule(
      enabled: true,
      unit: RecurrenceUnit.week,
      interval: 2,
      weekdays: {DateTime.monday, DateTime.wednesday},
    );
    final dates = rule.occurrencesBetween(
      startDate: DateTime(2026, 8, 3),
      fromDate: DateTime(2026, 8, 1),
      toDate: DateTime(2026, 9, 30),
    );
    expect(dates.toSet().length, dates.length);
    expect(dates.where((date) => date.weekday == DateTime.monday), isNotEmpty);
    expect(
      dates.where((date) => date.weekday == DateTime.wednesday),
      isNotEmpty,
    );
  });
}
