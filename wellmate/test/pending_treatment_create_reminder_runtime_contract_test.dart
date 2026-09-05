import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Home reconciles provisional pending-treatment reminders after schedule load', () {
    final source = File('lib/screens/home/home_screen_content.dart')
        .readAsStringSync();

    expect(source, contains('syncPendingTreatmentCreateReminders('));
    expect(source, contains('pendingTreatmentCreates,'));
    expect(source, contains('reminderTimeZone'));
    expect(source, contains('reminderIsPersian'));
  });

  test('NotificationProvider reuses one shared scheduler for provisional reminders', () {
    final source = File('lib/providers/notification_provider.dart')
        .readAsStringSync();

    expect(
      RegExp(r'LifeMateLocalReminderScheduler\s+_reminderScheduler')
          .allMatches(source),
      hasLength(1),
    );
    expect(
      source,
      contains(
        'PendingTreatmentCreateReminderSync(\n    scheduler: _reminderScheduler,',
      ),
    );
    expect(
      source,
      isNot(
        contains(
          'FlutterLocalNotificationsPlugin();\n  final FlutterLocalNotificationsPlugin',
        ),
      ),
    );
  });

  test(
    'canonical and provisional inexact fallback states cannot mask each other',
    () {
      final source = File('lib/providers/notification_provider.dart')
          .readAsStringSync();

      expect(source, contains('_canonicalInexactFallbackActive'));
      expect(source, contains('_pendingTreatmentInexactFallbackActive'));
      expect(
        source,
        contains(
          '_canonicalInexactFallbackActive || _pendingTreatmentInexactFallbackActive',
        ),
      );
    },
  );
}
