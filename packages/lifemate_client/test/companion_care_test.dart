import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  const engine = LifeMateCompanionCareEngine();
  final now = DateTime.utc(2026, 8, 27, 12);

  test('no exact scope produces no personalized guidance', () {
    expect(
      engine.select(
        phaseAllowed: false,
        wellbeingAllowed: false,
        cycleDay: 4,
        mood: 'low',
        energyLevel: 1,
        guidanceHistory: const [],
        supportActions: const [],
        locale: 'fa',
        nowUtc: now,
      ),
      isNull,
    );
  });

  test('shared wellbeing can produce non-diagnostic energy guidance', () {
    final value = engine.select(
      phaseAllowed: false,
      wellbeingAllowed: true,
      cycleDay: null,
      mood: null,
      energyLevel: 2,
      guidanceHistory: const [],
      supportActions: const [],
      locale: 'fa',
      nowUtc: now,
    );
    expect(value?.category, 'energy');
    expect(value?.message, contains('بدون حدس'));
  });

  test('global cooldown suppresses repeat guidance', () {
    expect(
      engine.select(
        phaseAllowed: true,
        wellbeingAllowed: false,
        cycleDay: 3,
        mood: null,
        energyLevel: null,
        guidanceHistory: [
          LifeMateCompanionGuidanceHistoryItem(
            guidanceId: 'other',
            shownAtUtc: now.subtract(const Duration(hours: 2)),
          ),
        ],
        supportActions: const [],
        locale: 'en',
        nowUtc: now,
      ),
      isNull,
    );
  });

  test('recent support action deduplicates matching suggestion', () {
    expect(
      engine.select(
        phaseAllowed: true,
        wellbeingAllowed: false,
        cycleDay: 3,
        mood: null,
        energyLevel: null,
        guidanceHistory: const [],
        supportActions: [
          LifeMateCompanionSupportActionHistoryItem(
            actionType: 'CheckIn',
            performedAtUtc: now.subtract(const Duration(hours: 2)),
          ),
        ],
        locale: 'en',
        nowUtc: now,
      ),
      isNull,
    );
  });

  test('copy is locale aware and content version is stable', () {
    final fa = engine.select(
      phaseAllowed: true,
      wellbeingAllowed: false,
      cycleDay: 3,
      mood: null,
      energyLevel: null,
      guidanceHistory: const [],
      supportActions: const [],
      locale: 'fa-IR',
      nowUtc: now,
    );
    final en = engine.select(
      phaseAllowed: true,
      wellbeingAllowed: false,
      cycleDay: 3,
      mood: null,
      energyLevel: null,
      guidanceHistory: const [],
      supportActions: const [],
      locale: 'en-US',
      nowUtc: now,
    );
    expect(fa?.contentVersion, LifeMateCompanionCareEngine.contentVersion);
    expect(fa?.locale, 'fa');
    expect(en?.locale, 'en');
    expect(fa?.message, isNot(equals(en?.message)));
  });
}
