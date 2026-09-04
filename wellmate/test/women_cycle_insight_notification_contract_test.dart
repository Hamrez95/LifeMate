import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Cycle Insight reuses shared local scheduler and stays permission-passive', () {
    final scheduler = File(
      'lib/screens/women_calendar/women_cycle_insight_notification_scheduler.dart',
    ).readAsStringSync();

    expect(scheduler, contains('women_cycle_insights'));
    expect(scheduler, contains('LifeMateLocalReminderScheduler'));
    expect(scheduler, contains('LifeMateReminderAccuracy.inexact'));
    expect(scheduler, contains('areNotificationsEnabled'));
    expect(scheduler, contains('NotificationVisibility.private'));
    expect(scheduler, contains('women-health:cycle-insight'));
    expect(scheduler, isNot(contains('.zonedSchedule(')));
    expect(scheduler, isNot(contains('requestNotificationsPermission')));
    expect(scheduler, isNot(contains('.initialize(')));
    expect(scheduler, isNot(contains('wellmate_treatment_reminders')));
  });

  test('Cycle Insight telemetry stores metadata only', () {
    final backend = File(
      '../supabase/functions/lifemate-api/women_insight_preferences_store.ts',
    ).readAsStringSync();
    final scheduler = File(
      'lib/screens/women_calendar/women_cycle_insight_notification_scheduler.dart',
    ).readAsStringSync();

    expect(backend, contains('women_cycle_insight_history'));
    expect(backend, contains('analytics_key'));
    expect(
      backend,
      contains(
        'on conflict(owner_person_id,insight_id,surface,occurred_on) do nothing',
      ),
    );
    expect(scheduler, contains("surface: 'local_notification'"));
    expect(scheduler, isNot(contains('privateNotes')));
    expect(scheduler, isNot(contains('painLevel')));
    expect(scheduler, isNot(contains('symptomObservations')));
  });
}
