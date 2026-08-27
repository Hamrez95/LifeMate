import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('inactive Women tab routes to V3 activation without local truth', () {
    final entry = File(
      'lib/screens/women_calendar/women_health_entry_screen.dart',
    ).readAsStringSync();
    final home = File('lib/screens/home/home_screen.dart').readAsStringSync();

    expect(entry, contains('getWomenCalendarProfile()'));
    expect(entry, contains('WomenHealthActivationV3Screen('));
    expect(entry, contains('WomenCompanionScreen('));
    expect(home, contains('WomenHealthEntryScreen('));
    expect(
      home,
      contains('Navigation availability is a feature capability'),
      reason: 'Profile activation must not hide the activation entry itself.',
    );
  });

  test('activation stays no-scroll and asks no intimate optional data', () {
    final source = File(
      'lib/screens/women_calendar/women_health_activation_v3_screen.dart',
    ).readAsStringSync();

    expect(source, contains('LifeMateOnboardingTheme.womenHealth'));
    expect(source, contains('LifeMateOnboardingScaffold('));
    expect(source, isNot(contains('SingleChildScrollView')));
    expect(source, isNot(contains('ListView(')));
    expect(source, contains('showAppDatePicker('));
    expect(source, contains("_cycleKnown = false"));
    expect(source, contains("_periodKnown = !_periodKnown"));
    expect(source, contains("_option('irregular'"));
    expect(source, contains("_option('unknown'"));
    expect(source, isNot(contains('TextField(')));
  });

  test('backend wrapper forbids fertility and private activation inference', () {
    final source = File(
      '../supabase/functions/lifemate-api/women_calendar_v3.ts',
    ).readAsStringSync();

    expect(source, contains('fertilityIntent'));
    expect(source, contains('tryingToConceive'));
    expect(source, contains('pregnancyIntent'));
    expect(source, contains('women_activation_private_field_forbidden'));
    expect(source, contains('metadata_json'));
    expect(source, contains('null, now()'));
  });
}
