import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:wellmate/screens/treatments/treatment_recurrence_editor.dart';

void main() {
  for (final hours in <int>[6, 8, 12, 24, 48]) {
    test('hourly recurrence keeps exact $hours-hour canonical interval', () {
      const anchor = TimeOfDay(hour: 8, minute: 15);
      final selection = TreatmentRecurrenceSelection.interval(
        unit: RecurrenceUnit.hour,
        interval: hours,
        anchor: anchor,
      );

      final rule = selection.rule();

      expect(rule.enabled, isTrue);
      expect(rule.unit, RecurrenceUnit.hour);
      expect(rule.interval, hours);
      expect(selection.anchorLocalTime, '08:15');
    });
  }

  test('48-hour recurrence remains 48 hours after rule reconstruction', () {
    final first = TreatmentRecurrenceSelection.interval(
      unit: RecurrenceUnit.hour,
      interval: 48,
      anchor: const TimeOfDay(hour: 23, minute: 55),
    );
    final persisted = first.rule();
    final reloaded = TreatmentRecurrenceSelection.interval(
      unit: persisted.unit,
      interval: persisted.interval,
      anchor: const TimeOfDay(hour: 23, minute: 55),
    );

    expect(reloaded.rule().interval, 48);
    expect(reloaded.anchorLocalTime, '23:55');
  });

  test('explicit-time mode never fabricates an hourly recurrence', () {
    const selection = TreatmentRecurrenceSelection.explicit();
    final rule = selection.rule();

    expect(selection.enabled, isFalse);
    expect(rule.enabled, isFalse);
  });

  test('non-hourly legacy recurrence remains representable without reinterpretation', () {
    final legacy = TreatmentRecurrenceSelection.interval(
      unit: RecurrenceUnit.week,
      interval: 2,
      anchor: const TimeOfDay(hour: 9, minute: 0),
    );

    final rule = legacy.rule();
    expect(rule.enabled, isTrue);
    expect(rule.unit, RecurrenceUnit.week);
    expect(rule.interval, 2);
    expect(legacy.anchorLocalTime, '09:00');
  });
}
