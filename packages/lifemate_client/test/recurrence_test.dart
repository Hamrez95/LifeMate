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

  test('every three days stops after exactly five occurrences', () {
    const rule = RecurrenceRule(
      enabled: true,
      unit: RecurrenceUnit.day,
      interval: 3,
      maxOccurrences: 5,
    );
    final dates = rule.occurrencesBetween(
      startDate: DateTime(2026, 8, 1),
      fromDate: DateTime(2026, 8, 1),
      toDate: DateTime(2026, 9, 30),
    );
    expect(dates, [
      DateTime(2026, 8, 1),
      DateTime(2026, 8, 4),
      DateTime(2026, 8, 7),
      DateTime(2026, 8, 10),
      DateTime(2026, 8, 13),
    ]);
  });

  test('count limit is series-wide when querying a later window', () {
    const rule = RecurrenceRule(
      enabled: true,
      unit: RecurrenceUnit.day,
      interval: 3,
      maxOccurrences: 5,
    );
    final dates = rule.occurrencesBetween(
      startDate: DateTime(2026, 8, 1),
      fromDate: DateTime(2026, 8, 9),
      toDate: DateTime(2026, 9, 30),
    );
    expect(dates, [DateTime(2026, 8, 10), DateTime(2026, 8, 13)]);
  });

  test('end date wins before the requested range upper bound', () {
    final rule = RecurrenceRule(
      enabled: true,
      unit: RecurrenceUnit.day,
      interval: 2,
      endDate: DateTime(2026, 8, 6),
    );
    final dates = rule.occurrencesBetween(
      startDate: DateTime(2026, 8, 1),
      fromDate: DateTime(2026, 8, 1),
      toDate: DateTime(2026, 9, 1),
    );
    expect(dates, [
      DateTime(2026, 8, 1),
      DateTime(2026, 8, 3),
      DateTime(2026, 8, 5),
    ]);
  });

  test('yearly leap-day recurrence clamps deterministically', () {
    const rule = RecurrenceRule(
      enabled: true,
      unit: RecurrenceUnit.year,
      interval: 1,
    );
    final dates = rule.occurrencesBetween(
      startDate: DateTime(2024, 2, 29),
      fromDate: DateTime(2024, 1, 1),
      toDate: DateTime(2028, 12, 31),
    );
    expect(dates, [
      DateTime(2024, 2, 29),
      DateTime(2025, 2, 28),
      DateTime(2026, 2, 28),
      DateTime(2027, 2, 28),
      DateTime(2028, 2, 29),
    ]);
  });

  test('version and count round-trip through product JSON', () {
    final rule = RecurrenceRule.fromJson({
      'version': 2,
      'enabled': true,
      'unit': 'week',
      'interval': 2,
      'weekdays': [DateTime.monday, DateTime.friday],
      'maxOccurrences': 8,
      'endDate': '2026-12-31',
    });
    expect(rule.version, 2);
    expect(rule.maxOccurrences, 8);
    expect(rule.toJson(), {
      'version': 2,
      'enabled': true,
      'unit': 'week',
      'interval': 2,
      'weekdays': [DateTime.monday, DateTime.friday],
      'endDate': '2026-12-31',
      'maxOccurrences': 8,
    });
  });

  test('count bound resolves to server-compatible end date', () {
    const rule = RecurrenceRule(
      enabled: true,
      unit: RecurrenceUnit.day,
      interval: 3,
      maxOccurrences: 5,
    );
    expect(rule.persistenceEndDate(DateTime(2026, 8, 1)), DateTime(2026, 8, 13));
  });

  test('earlier explicit recurrence end wins over count boundary', () {
    final rule = RecurrenceRule(
      enabled: true,
      unit: RecurrenceUnit.month,
      interval: 1,
      maxOccurrences: 6,
      endDate: DateTime(2026, 10, 15),
    );
    expect(rule.persistenceEndDate(DateTime(2026, 8, 31)), DateTime(2026, 10, 15));
  });
}
