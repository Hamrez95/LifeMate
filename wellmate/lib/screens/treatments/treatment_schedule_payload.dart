import 'package:flutter/material.dart';

/// Builds the API schedule payload as the cartesian product of selected
/// weekdays and local times. The result is deterministic, de-duplicated and
/// sorted so retries and review screens use the same payload ordering.
List<Map<String, String>> buildTreatmentSchedules({
  required Iterable<int> weekdays,
  required Iterable<TimeOfDay> times,
  required Map<int, String> backendWeekdays,
}) {
  final normalizedDays = weekdays.toSet().toList()..sort();
  final normalizedMinutes = times
      .map((time) => time.hour * 60 + time.minute)
      .toSet()
      .toList()
    ..sort();

  if (normalizedDays.isEmpty || normalizedMinutes.isEmpty) {
    return const <Map<String, String>>[];
  }

  return [
    for (final day in normalizedDays)
      for (final minuteOfDay in normalizedMinutes)
        {
          'dayOfWeek': backendWeekdays[day] ??
              (throw ArgumentError.value(
                day,
                'weekdays',
                'Missing backend weekday mapping.',
              )),
          'localTime':
              '${(minuteOfDay ~/ 60).toString().padLeft(2, '0')}:'
              '${(minuteOfDay % 60).toString().padLeft(2, '0')}',
        },
  ];
}

String formatTreatmentTime(TimeOfDay time) =>
    '${time.hour.toString().padLeft(2, '0')}:'
    '${time.minute.toString().padLeft(2, '0')}';
