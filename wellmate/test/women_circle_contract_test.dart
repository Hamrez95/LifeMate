import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Circle UI is additive and privacy-first', () {
    final launcher = File(
      'lib/screens/women_calendar/women_daily_log_launcher.dart',
    ).readAsStringSync();
    final card = File(
      'lib/screens/women_calendar/women_circle_card.dart',
    ).readAsStringSync();

    expect(launcher, contains('WomenCircleCard'));
    expect(launcher, contains('WomenInsightsAnalyticsCards'));
    expect(card, contains('ساخت Circle'));
    expect(card, contains('Create Circle'));
    expect(card, contains('planning_only'));
    expect(card, contains('limited_context'));
    expect(card, contains('No sharing'));
    expect(card, contains("type != 'friend'"));
    expect(card, contains('Membership alone never shares health data.'));
    expect(card, contains('symptoms, pain, notes and raw dates remain private'));
  });

  test('Circle backend returns aggregate planning rather than raw health fields', () {
    final store = File(
      '../supabase/functions/lifemate-api/women_circle_store.ts',
    ).readAsStringSync();

    expect(store, contains('aggregateCirclePlanningWindow'));
    expect(store, contains('planningSummary: planning'));
    expect(store, contains("sharing_mode='none'"));
    expect(store, contains('circle.member_removed'));
    expect(store, isNot(contains('privateNotes:')));
    expect(store, isNot(contains('painLevel:')));
    expect(store, isNot(contains('symptoms:')));
  });
}
