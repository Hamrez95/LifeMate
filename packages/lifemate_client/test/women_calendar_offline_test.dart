import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test('offline estimate accepts only the canonical server algorithm version', () {
    final estimate = WomenCalendarOfflineEngine.calculateFromCanonicalSnapshot(
      profile: const <String, dynamic>{
        'algorithmVersion': 'calendar-estimate-v1',
        'lastPeriodStart': '2026-08-26',
        'cycleLength': 28,
        'periodLength': 5,
      },
      episodes: const <Map<String, dynamic>>[
        <String, dynamic>{'startedOn': '2026-06-03'},
        <String, dynamic>{'startedOn': '2026-07-01'},
        <String, dynamic>{'startedOn': '2026-07-29'},
        <String, dynamic>{'startedOn': '2026-08-26'},
      ],
      today: DateTime(2026, 9, 5),
    );

    expect(estimate.cycleDay, 11);
    expect(estimate.cycleLength, 28);
    expect(estimate.confidence, WomenCycleEstimateConfidence.high);
    expect(estimate.fertilityEstimateReliable, isTrue);
  });

  test('algorithm mismatch fails closed instead of silently changing history', () {
    expect(
      () => WomenCalendarOfflineEngine.calculateFromCanonicalSnapshot(
        profile: const <String, dynamic>{
          'algorithmVersion': 'calendar-estimate-v2',
          'lastPeriodStart': '2026-08-26',
          'cycleLength': 28,
          'periodLength': 5,
        },
        episodes: const <Map<String, dynamic>>[],
      ),
      throwsA(isA<WomenCalendarAlgorithmVersionMismatchException>()),
    );
  });

  test('pregnancy and postpartum lifecycle suppress personal cycle reminders', () {
    for (final state in <WomenHealthLifecycleState>[
      WomenHealthLifecycleState.pausedForPregnancy,
      WomenHealthLifecycleState.postpartumRecovery,
      WomenHealthLifecycleState.resumable,
    ]) {
      expect(
        WomenCalendarOfflineEngine.shouldSchedulePersonalCycleReminders(
          womenHealthEnabled: true,
          remindersEnabled: true,
          lifecycleState: state,
        ),
        isFalse,
      );
    }

    expect(
      WomenCalendarOfflineEngine.shouldSchedulePersonalCycleReminders(
        womenHealthEnabled: true,
        remindersEnabled: true,
        lifecycleState: WomenHealthLifecycleState.active,
      ),
      isTrue,
    );
  });

  test('lifecycle parser mirrors the canonical server wire values', () {
    expect(
      WomenHealthLifecycleState.parse('paused_for_pregnancy'),
      WomenHealthLifecycleState.pausedForPregnancy,
    );
    expect(
      WomenHealthLifecycleState.parse('postpartum_recovery'),
      WomenHealthLifecycleState.postpartumRecovery,
    );
    expect(
      () => WomenHealthLifecycleState.parse('unknown'),
      throwsA(isA<FormatException>()),
    );
  });
}
