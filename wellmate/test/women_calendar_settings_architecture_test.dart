import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('women calendar settings contains persistent configuration only', () {
    final source = File(
      'lib/screens/women_calendar/women_calendar_screen.dart',
    ).readAsStringSync();
    expect(source, contains("ValueKey('women-calendar-settings-only')"));
    expect(source, isNot(contains('WomenDailyCheckInCard(')));
    expect(source, isNot(contains("includeDailyCheckIn")));
    expect(source, isNot(contains("dailyCheckIn:")));
    expect(source, isNot(contains('_saveDailyCheckIn')));
  });
}
