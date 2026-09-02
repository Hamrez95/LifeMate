import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  group('LifeMateAppLockPolicy', () {
    final now = DateTime.utc(2026, 9, 2, 12);

    test('disabled policy never blocks the UI', () {
      const policy = LifeMateAppLockPolicy.disabled();

      expect(
        policy.requiresUnlock(now: now, coldStart: true),
        isFalse,
      );
      expect(
        policy.requiresUnlock(
          now: now,
          lastUnlockedAt: now.subtract(const Duration(days: 1)),
        ),
        isFalse,
      );
    });

    test('enabled policy locks on cold start', () {
      final policy = LifeMateAppLockPolicy(enabled: true);

      expect(policy.requiresUnlock(now: now, coldStart: true), isTrue);
    });

    test('enabled policy locks again only after the configured timeout', () {
      final policy = LifeMateAppLockPolicy(
        enabled: true,
        relockAfter: const Duration(minutes: 5),
      );

      expect(
        policy.requiresUnlock(
          now: now,
          lastUnlockedAt: now.subtract(const Duration(minutes: 4)),
        ),
        isFalse,
      );
      expect(
        policy.requiresUnlock(
          now: now,
          lastUnlockedAt: now.subtract(const Duration(minutes: 5)),
        ),
        isTrue,
      );
    });

    test('missing unlock history fails closed when lock is enabled', () {
      final policy = LifeMateAppLockPolicy(enabled: true);

      expect(policy.requiresUnlock(now: now), isTrue);
    });
  });
}
