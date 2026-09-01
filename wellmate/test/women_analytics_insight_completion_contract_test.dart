import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('full analytics is reachable and recorded-facts only', () {
    final launcher = File(
      'lib/screens/women_calendar/women_daily_log_launcher.dart',
    ).readAsStringSync();
    final analytics = File(
      'lib/screens/women_calendar/women_cycle_analytics_screen.dart',
    ).readAsStringSync();

    expect(launcher, contains('WomenCycleAnalyticsScreen'));
    expect(launcher, contains("context.tr('women.analytics.full')"));
    expect(analytics, contains('Recorded facts summary'));
    expect(analytics, contains('Recurring symptoms'));
    expect(analytics, contains('Recorded flow'));
    expect(analytics, contains('Recorded blood appearance'));
    expect(analytics, contains('Recorded texture'));
    expect(analytics, contains('does not provide a diagnosis'));
  });

  test('Cycle Insight controls persist independently from OS permission', () {
    final card = File(
      'lib/screens/women_calendar/women_insight_preferences_card.dart',
    ).readAsStringSync();
    final api = File(
      'lib/screens/women_calendar/women_insight_preferences_api.dart',
    ).readAsStringSync();
    final backend = File(
      '../supabase/functions/lifemate-api/women_insight_preferences_store.ts',
    ).readAsStringSync();

    expect(card, contains('In-app insights work independently'));
    expect(card, contains('Cycle Insight notifications'));
    expect(card, contains("'low'"));
    expect(card, contains("'balanced'"));
    expect(card, contains("'high'"));
    expect(api, contains("'insightPreferences': preferences"));
    expect(backend, contains('stale_cycle_insight_preferences'));
    expect(backend, contains('notifications_enabled'));
  });
}
