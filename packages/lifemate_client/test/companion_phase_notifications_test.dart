import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  const engine = LifeMateCompanionPhaseNotificationEngine();
  final now = DateTime.utc(2026, 8, 28, 10);

  LifeMateCompanionPhaseNotification? select({
    bool receive = true,
    bool phase = true,
    bool timing = true,
    bool preference = true,
    int cycleDay = 1,
    String detailedPhase = 'period',
    int daysUntilNextPeriod = 27,
    String confidence = 'high',
    String pattern = 'regular',
    List<LifeMateCompanionPhaseNotificationHistoryItem> history = const [],
  }) => engine.select(
    receivePhaseNotifications: receive,
    viewPhaseSummary: phase,
    viewPeriodTiming: timing,
    caregiverNotificationsEnabled: preference,
    cycleStart: '2026-08-28',
    cycleDay: cycleDay,
    detailedPhase: detailedPhase,
    daysUntilNextPeriod: daysUntilNextPeriod,
    nextPeriodStart: '2026-09-25',
    confidence: confidence,
    cyclePattern: pattern,
    history: history,
    locale: 'en',
    nowUtc: now,
  );

  test('requires independent receive scope and caregiver preference', () {
    expect(select(receive: false), isNull);
    expect(select(preference: false), isNull);
    expect(select(phase: false), isNull);
  });

  test('recorded period start additionally requires timing scope', () {
    expect(select(timing: false), isNull);
    final candidate = select();
    expect(candidate?.guidanceId, 'notify.phase.period_start.2026-08-28');
    expect(candidate?.isPrediction, isFalse);
  });

  test('low-confidence or variable cycle never produces predictive copy', () {
    expect(
      select(
        cycleDay: 26,
        detailedPhase: 'luteal',
        daysUntilNextPeriod: 2,
        confidence: 'low',
      ),
      isNull,
    );
    expect(
      select(
        cycleDay: 26,
        detailedPhase: 'luteal',
        daysUntilNextPeriod: 2,
        pattern: 'variable',
      ),
      isNull,
    );
  });

  test('fertility and ovulation phases are excluded from #106', () {
    expect(
      select(cycleDay: 13, detailedPhase: 'fertile', daysUntilNextPeriod: 15),
      isNull,
    );
    expect(
      select(cycleDay: 14, detailedPhase: 'ovulation', daysUntilNextPeriod: 14),
      isNull,
    );
  });

  test('approaching-period prediction is explicitly uncertain', () {
    final candidate = select(
      cycleDay: 26,
      detailedPhase: 'luteal',
      daysUntilNextPeriod: 2,
    );
    expect(candidate?.isPrediction, isTrue);
    expect(candidate?.fullBody.toLowerCase(), contains('estimate'));
  });

  test('stable history key deduplicates the same cycle notification', () {
    final first = select();
    final second = select(
      history: [
        LifeMateCompanionPhaseNotificationHistoryItem(
          guidanceId: first!.guidanceId,
          shownAtUtc: now.subtract(const Duration(days: 3)),
        ),
      ],
    );
    expect(second, isNull);
  });

  test('global cadence prevents phase notification spam', () {
    final result = select(
      cycleDay: 18,
      detailedPhase: 'luteal',
      daysUntilNextPeriod: 10,
      history: [
        LifeMateCompanionPhaseNotificationHistoryItem(
          guidanceId: 'notify.phase.other.2026-08-28',
          shownAtUtc: now.subtract(const Duration(hours: 12)),
        ),
      ],
    );
    expect(result, isNull);
  });

  test('private lock-screen copy contains no period or phase detail', () {
    final candidate = select()!;
    final privateCopy = candidate.privateBody.toLowerCase();
    expect(privateCopy, isNot(contains('period')));
    expect(privateCopy, isNot(contains('cycle')));
    expect(privateCopy, isNot(contains('phase')));
  });
}
