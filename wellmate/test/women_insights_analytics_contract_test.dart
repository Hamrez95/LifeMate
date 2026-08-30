import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Women Health surfaces evidence-aware in-app insights and analytics', () {
    final cards = File(
      'lib/screens/women_calendar/women_insights_analytics_cards.dart',
    ).readAsStringSync();
    final launcher = File(
      'lib/screens/women_calendar/women_daily_log_launcher.dart',
    ).readAsStringSync();

    expect(cards, contains('Cycle insight'));
    expect(cards, contains('not a medical diagnosis'));
    expect(cards, contains('My stats & patterns'));
    expect(cards, contains('Recorded facts only'));
    expect(cards, contains('episodes.length < 3'));
    expect(cards, contains('e.value >= 2'));
    expect(launcher, contains('WomenInsightsAnalyticsCards'));
  });
}
