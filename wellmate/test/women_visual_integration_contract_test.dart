import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('canonical Women Health screen keeps prior design and adds rich log CTA', () {
    final companion = File(
      'lib/screens/women_calendar/women_companion_screen.dart',
    ).readAsStringSync();
    final hero = File(
      'lib/screens/women_calendar/women_companion_people_hero.dart',
    ).readAsStringSync();

    expect(companion, contains('WomenCalendarMonthCard('));
    expect(companion, contains('_DailyCheckInCard('));
    expect(companion, contains('_DailyTipCard('));
    expect(companion, contains("item['canViewWomenCalendar'] != true"));
    expect(hero, contains('WomenDailyLogLauncher(date: DateTime.now())'));
  });

  test('partner badge is presentation-only on already eligible avatars', () {
    final hero = File(
      'lib/screens/women_calendar/women_companion_people_hero.dart',
    ).readAsStringSync();

    expect(
      hero,
      contains("relationship['relationshipType']?.toString().toLowerCase() == 'partner'"),
    );
    expect(hero, contains('PartnerAvatarBadge('));
    expect(hero, isNot(contains('canViewWomenCalendar = true')));
  });

  test('rich daily log persists canonical symptom observations', () {
    final backend = File(
      '../supabase/functions/lifemate-api/women_calendar_rich_period.ts',
    ).readAsStringSync();

    expect(backend, contains('canonicalizeLegacySymptoms(body.symptoms)'));
    expect(backend, contains('symptom_observations'));
    expect(backend, contains('symptom_schema_version'));
    expect(backend, contains('mergeLegacySymptomsIntoObservations'));
  });

  test('daily-log canonical refresh regenerates shared local reminders', () {
    final launcher = File(
      'lib/screens/women_calendar/women_daily_log_launcher.dart',
    ).readAsStringSync();

    expect(launcher, contains('canonicalRefreshSucceeded = true'));
    expect(launcher, contains('if (canonicalRefreshSucceeded)'));
    expect(launcher, contains('await _refreshCanonicalReminders();'));
    expect(launcher, contains('getWomenCalendarDashboard('));
    expect(launcher, contains('WomenCycleInsightNotificationScheduler().sync('));
    expect(launcher, contains('await offline.readCachedServerDay(widget.date)'));
  });
}
