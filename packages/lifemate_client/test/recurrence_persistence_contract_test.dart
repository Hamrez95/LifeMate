import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test('every three days for five occurrences persists the fifth date', () {
    const rule = RecurrenceRule(
      enabled: true,
      unit: RecurrenceUnit.day,
      interval: 3,
      maxOccurrences: 5,
    );

    expect(
      rule.persistenceEndDate(DateTime(2026, 8, 1)),
      DateTime(2026, 8, 13),
    );
  });

  test('weekly count boundary follows selected weekdays from series start', () {
    const rule = RecurrenceRule(
      enabled: true,
      unit: RecurrenceUnit.week,
      interval: 2,
      weekdays: {DateTime.monday, DateTime.wednesday},
      maxOccurrences: 4,
    );

    expect(
      rule.persistenceEndDate(DateTime(2026, 8, 3)),
      DateTime(2026, 8, 19),
    );
  });

  test('explicit earlier end date remains authoritative', () {
    final rule = RecurrenceRule(
      enabled: true,
      unit: RecurrenceUnit.month,
      interval: 1,
      maxOccurrences: 6,
      endDate: DateTime(2026, 10, 15),
    );

    expect(
      rule.persistenceEndDate(DateTime(2026, 8, 31)),
      DateTime(2026, 10, 15),
    );
  });
}
