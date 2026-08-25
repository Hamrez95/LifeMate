import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  final scheduled = DateTime.utc(2026, 8, 25, 10);

  test('resolved treatment cancels every future notification stage', () {
    final decision = LifeMateNotificationIntelligence.evaluate(
      personId: 'person-a',
      sourceId: 'dose-1',
      status: 'taken',
      scheduledAtUtc: scheduled,
      nowUtc: scheduled.add(const Duration(hours: 1)),
      stage: LifeMateNotificationStage.caregiverEscalation,
    );

    expect(decision.shouldNotify, isFalse);
    expect(decision.shouldCancel, isTrue);
  });

  test('missed alert waits for deterministic grace period', () {
    final beforeGrace = LifeMateNotificationIntelligence.evaluate(
      personId: 'person-a',
      sourceId: 'dose-1',
      status: 'scheduled',
      scheduledAtUtc: scheduled,
      nowUtc: scheduled.add(const Duration(minutes: 14)),
      stage: LifeMateNotificationStage.alert,
    );
    final afterGrace = LifeMateNotificationIntelligence.evaluate(
      personId: 'person-a',
      sourceId: 'dose-1',
      status: 'scheduled',
      scheduledAtUtc: scheduled,
      nowUtc: scheduled.add(const Duration(minutes: 15)),
      stage: LifeMateNotificationStage.alert,
    );

    expect(beforeGrace.shouldNotify, isFalse);
    expect(afterGrace.shouldNotify, isTrue);
  });

  test('caregiver escalation requires authorization and preference', () {
    final denied = LifeMateNotificationIntelligence.evaluate(
      personId: 'person-a',
      sourceId: 'dose-1',
      status: 'missed',
      scheduledAtUtc: scheduled,
      nowUtc: scheduled.add(const Duration(hours: 1)),
      stage: LifeMateNotificationStage.caregiverEscalation,
      relationshipAuthorized: false,
    );
    final allowed = LifeMateNotificationIntelligence.evaluate(
      personId: 'person-a',
      sourceId: 'dose-1',
      status: 'missed',
      scheduledAtUtc: scheduled,
      nowUtc: scheduled.add(const Duration(hours: 1)),
      stage: LifeMateNotificationStage.caregiverEscalation,
      relationshipAuthorized: true,
      preferenceEnabled: true,
    );

    expect(denied.shouldNotify, isFalse);
    expect(allowed.shouldNotify, isTrue);
  });

  test('priority never becomes high without explicit metadata', () {
    final normal = LifeMateNotificationIntelligence.evaluate(
      personId: 'person-a',
      sourceId: 'dose-1',
      status: 'missed',
      scheduledAtUtc: scheduled,
      nowUtc: scheduled.add(const Duration(hours: 4)),
      stage: LifeMateNotificationStage.alert,
    );
    final explicit = LifeMateNotificationIntelligence.evaluate(
      personId: 'person-a',
      sourceId: 'dose-1',
      status: 'missed',
      scheduledAtUtc: scheduled,
      nowUtc: scheduled.add(const Duration(hours: 4)),
      stage: LifeMateNotificationStage.alert,
      explicitHighPriority: true,
    );

    expect(normal.priority, LifeMateNotificationPriority.normal);
    expect(explicit.priority, LifeMateNotificationPriority.high);
  });

  test('deduplication key is stable across timezone/rebuild calls', () {
    final first = LifeMateNotificationIntelligence.deduplicationKey(
      personId: 'person-a',
      sourceId: 'dose-1',
      stage: LifeMateNotificationStage.reminder,
    );
    final second = LifeMateNotificationIntelligence.deduplicationKey(
      personId: 'person-a',
      sourceId: 'dose-1',
      stage: LifeMateNotificationStage.reminder,
    );

    expect(first, second);
    expect(first, 'reminder:person-a:dose-1');
  });

  test('deduplicate keeps cancellation over an active duplicate', () {
    const active = LifeMateNotificationDecision(
      stage: LifeMateNotificationStage.alert,
      priority: LifeMateNotificationPriority.normal,
      deduplicationKey: 'alert:person-a:dose-1',
      shouldNotify: true,
      shouldCancel: false,
    );
    const cancelled = LifeMateNotificationDecision(
      stage: LifeMateNotificationStage.alert,
      priority: LifeMateNotificationPriority.normal,
      deduplicationKey: 'alert:person-a:dose-1',
      shouldNotify: false,
      shouldCancel: true,
    );

    final result = LifeMateNotificationIntelligence.deduplicate([
      active,
      cancelled,
    ]);

    expect(result, hasLength(1));
    expect(result.single.shouldCancel, isTrue);
  });
}
