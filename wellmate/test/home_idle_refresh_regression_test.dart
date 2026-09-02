import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Home does not contain a periodic foreground refresh loop', () {
    final source = File('lib/screens/home/home_screen.dart').readAsStringSync();

    expect(
      source,
      isNot(contains('_backgroundRefreshTimer')),
      reason: 'Idle Home must not periodically bump refresh revisions.',
    );
    expect(
      source,
      isNot(contains('_backgroundRefreshInterval')),
      reason: 'Periodic stale timers caused repeated full-page reloads.',
    );
    expect(
      source,
      isNot(contains('_refreshActiveTabIfStale')),
      reason: 'Tab data should refresh only on meaningful lifecycle/navigation events.',
    );
  });
}
