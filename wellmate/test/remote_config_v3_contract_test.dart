import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('WellMate startup is wrapped by the shared runtime config gate', () {
    final source = File('lib/main.dart').readAsStringSync();
    expect(source, contains('LifeMateRuntimeConfigGate('));
    expect(source, contains("product: 'wellmate'"));
    expect(source, contains('currentVersion: wellMateAppVersion'));
  });

  test('Women Health entry consumes the server-provided kill switch', () {
    final source = File(
      'lib/screens/women_calendar/women_health_entry_screen.dart',
    ).readAsStringSync();
    expect(source, contains('LifeMateRuntimeConfigScope.maybeOf(context)'));
    expect(source, contains("'client.women_calendar.enabled'"));
    expect(source, contains('defaultValue: false'));
  });
}
