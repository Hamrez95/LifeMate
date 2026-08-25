import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test('future occurrence never alerts even if a stale status says missed', () {
    final scheduled = DateTime.utc(2026, 8, 25, 12);
    final decision = LifeMateNotificationIntelligence.evaluate(
      personId: 'person-a',
      sourceId: 'dose-a',
      status: 'missed',
      scheduledAtUtc: scheduled,
      nowUtc: scheduled.subtract(const Duration(minutes: 1)),
      stage: LifeMateNotificationStage.caregiverEscalation,
    );

    expect(decision.shouldNotify, isFalse);
    expect(decision.shouldCancel, isTrue);
  });
}
