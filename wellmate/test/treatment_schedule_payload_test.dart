import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wellmate/screens/treatments/treatment_schedule_payload.dart';

void main() {
  const backendDays = <int, String>{
    DateTime.monday: 'monday',
    DateTime.tuesday: 'tuesday',
    DateTime.wednesday: 'wednesday',
    DateTime.thursday: 'thursday',
    DateTime.friday: 'friday',
    DateTime.saturday: 'saturday',
    DateTime.sunday: 'sunday',
  };

  test('builds a deterministic weekday by time cartesian product', () {
    final schedules = buildTreatmentSchedules(
      weekdays: const [DateTime.wednesday, DateTime.monday],
      times: const [TimeOfDay(hour: 21, minute: 0), TimeOfDay(hour: 8, minute: 5)],
      backendWeekdays: backendDays,
    );

    expect(schedules, [
      {'dayOfWeek': 'monday', 'localTime': '08:05'},
      {'dayOfWeek': 'monday', 'localTime': '21:00'},
      {'dayOfWeek': 'wednesday', 'localTime': '08:05'},
      {'dayOfWeek': 'wednesday', 'localTime': '21:00'},
    ]);
  });

  test('removes duplicate weekdays and times', () {
    final schedules = buildTreatmentSchedules(
      weekdays: const [DateTime.monday, DateTime.monday],
      times: const [TimeOfDay(hour: 9, minute: 0), TimeOfDay(hour: 9, minute: 0)],
      backendWeekdays: backendDays,
    );

    expect(schedules, [
      {'dayOfWeek': 'monday', 'localTime': '09:00'},
    ]);
  });

  test('returns an empty payload when no day or time is selected', () {
    expect(
      buildTreatmentSchedules(
        weekdays: const [],
        times: const [TimeOfDay(hour: 9, minute: 0)],
        backendWeekdays: backendDays,
      ),
      isEmpty,
    );
    expect(
      buildTreatmentSchedules(
        weekdays: const [DateTime.monday],
        times: const [],
        backendWeekdays: backendDays,
      ),
      isEmpty,
    );
  });
}
