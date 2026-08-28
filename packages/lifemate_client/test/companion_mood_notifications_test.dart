import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  const engine = LifeMateCompanionMoodNotificationEngine();
  final now = DateTime.utc(2026, 8, 28, 11);

  LifeMateCompanionMoodNotification? select({
    bool receive = true,
    bool shared = true,
    bool caregiver = true,
    String mood = 'low',
    int energy = 2,
    DateTime? updated,
    List<LifeMateCompanionMoodNotificationHistoryItem> history = const [],
  }) => engine.select(
    receiveMoodSupportNotifications: receive,
    viewSharedWellbeing: shared,
    caregiverNotificationsEnabled: caregiver,
    loggedOn: '2026-08-28',
    mood: mood,
    energyLevel: energy,
    updatedAtUtc: updated ?? now.subtract(const Duration(minutes: 10)),
    history: history,
    locale: 'en',
    nowUtc: now,
  );

  test('requires exact mood notification scope, shared wellbeing and caregiver preference', () {
    expect(select(receive: false), isNull);
    expect(select(shared: false), isNull);
    expect(select(caregiver: false), isNull);
  });

  test('low mood produces non-diagnostic supportive copy', () {
    final result = select();
    expect(result?.trigger, 'mood');
    final copy = result!.fullBody.toLowerCase();
    expect(copy, isNot(contains('depress')));
    expect(copy, isNot(contains('anxiety')));
    expect(copy, isNot(contains('crisis')));
    expect(copy, isNot(contains('treatment')));
  });

  test('low energy is a fallback trigger when mood is not low', () {
    final result = select(mood: 'neutral', energy: 1);
    expect(result?.trigger, 'energy');
  });

  test('one entry never fans out to mood and energy notifications', () {
    final result = select(mood: 'overwhelmed', energy: 1);
    expect(result?.guidanceId, 'notify.mood.check_in.2026-08-28');
  });

  test('stale shared entry cannot trigger a new notification', () {
    expect(
      select(updated: now.subtract(const Duration(hours: 9))),
      isNull,
    );
  });

  test('retry or same-day edit does not duplicate the same notification', () {
    final result = select(
      history: [
        LifeMateCompanionMoodNotificationHistoryItem(
          guidanceId: 'notify.mood.check_in.2026-08-28',
          shownAtUtc: now.subtract(const Duration(days: 1)),
        ),
      ],
    );
    expect(result, isNull);
  });

  test('global cooldown prevents another wellbeing alert from the same day', () {
    final result = select(
      mood: 'neutral',
      energy: 1,
      history: [
        LifeMateCompanionMoodNotificationHistoryItem(
          guidanceId: 'notify.mood.some-other.2026-08-28',
          shownAtUtc: now.subtract(const Duration(hours: 2)),
        ),
      ],
    );
    expect(result, isNull);
  });

  test('private lock-screen copy contains no mood or energy detail', () {
    final body = select()!.privateBody.toLowerCase();
    expect(body, isNot(contains('mood')));
    expect(body, isNot(contains('energy')));
    expect(body, isNot(contains('low')));
  });
}
