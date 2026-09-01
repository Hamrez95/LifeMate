import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('migrated Women daily-log launcher uses semantic localization keys', () {
    final source = File(
      'lib/screens/women_calendar/women_daily_log_launcher.dart',
    ).readAsStringSync();

    expect(source, contains("context.tr('women.dailyLog.title')"));
    expect(source, contains("context.tr('women.dailyLog.logToday')"));
    expect(source, contains("context.tr('women.analytics.full')"));
    expect(source, isNot(contains('LifeMateRuntimeLocale.select(')));
    expect(source, isNot(contains("rtl ? '")));
  });

  test('migrated Women companion hero uses semantic localization keys', () {
    final source = File(
      'lib/screens/women_calendar/women_companion_people_hero.dart',
    ).readAsStringSync();

    expect(source, contains("context.tr('women.companion.greeting')"));
    expect(source, contains("context.tr('women.companion.partner')"));
    expect(source, contains("'women.companion.stackSemantic'"));
    expect(source, isNot(contains('LifeMateRuntimeLocale.select(')));
  });

  test('migrated Women entry uses semantic localization keys', () {
    final source = File(
      'lib/screens/women_calendar/women_health_entry_screen.dart',
    ).readAsStringSync();

    expect(source, contains("context.tr('women.entry.statusLoadFailed')"));
    expect(source, contains("context.tr('women.entry.unavailable')"));
    expect(source, contains("context.tr('common.retry')"));
    expect(source, isNot(contains('LifeMateRuntimeLocale.select(')));
  });

  test('migrated Women activation uses semantic localization keys and locale direction', () {
    final source = File(
      'lib/screens/women_calendar/women_health_activation_v3_screen.dart',
    ).readAsStringSync();

    expect(source, contains("context.tr('women.activation.activateTitle')"));
    expect(source, contains("'women.activation.progress'"));
    expect(source, contains('context.lifeMateLocale.textDirection'));
    expect(source, isNot(contains('LifeMateRuntimeLocale.select(')));
    expect(source, isNot(contains('bool get _isPersian')));
  });
}
