import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  const engine = LifeMateCompanionCareEngine();
  final now = DateTime.utc(2026, 8, 28, 8);

  test('fails closed when no exact companion scope is allowed', () {
    final result = engine.select(
      phaseAllowed: false,
      wellbeingAllowed: false,
      cycleDay: 12,
      mood: 'low',
      energyLevel: 1,
      guidanceHistory: const [],
      supportActions: const [],
      locale: 'fa',
      nowUtc: now,
    );
    expect(result, isNull);
  });

  test('phase-only guidance never exposes wellbeing support action', () {
    final result = engine.select(
      phaseAllowed: true,
      wellbeingAllowed: false,
      cycleDay: 12,
      mood: 'overwhelmed',
      energyLevel: 1,
      guidanceHistory: const [],
      supportActions: const [],
      locale: 'en-US',
      nowUtc: now,
    );
    expect(result?.category, 'phase');
    expect(result?.supportActionType, isNull);
    expect(result?.locale, 'en');
  });

  test('uses Persian versioned wellbeing guidance from allowed summary only', () {
    final result = engine.select(
      phaseAllowed: false,
      wellbeingAllowed: true,
      cycleDay: null,
      mood: 'neutral',
      energyLevel: 1,
      guidanceHistory: const [],
      supportActions: const [],
      locale: 'fa-IR',
      nowUtc: now,
    );
    expect(result?.category, 'energy');
    expect(result?.contentVersion, LifeMateCompanionCareEngine.contentVersion);
    expect(result?.locale, 'fa');
    expect(result?.supportActionType, 'chores');
  });

  test('global persisted history cooldown suppresses another suggestion', () {
    final result = engine.select(
      phaseAllowed: true,
      wellbeingAllowed: true,
      cycleDay: 12,
      mood: 'low',
      energyLevel: 2,
      guidanceHistory: [
        LifeMateCompanionGuidanceHistoryItem(
          guidanceId: 'some.other.guidance',
          shownAtUtc: now.subtract(const Duration(hours: 17)),
        ),
      ],
      supportActions: const [],
      locale: 'en',
      nowUtc: now,
    );
    expect(result, isNull);
  });

  test('same guidance is deduplicated across the persisted cooldown', () {
    final result = engine.select(
      phaseAllowed: false,
      wellbeingAllowed: true,
      cycleDay: null,
      mood: 'neutral',
      energyLevel: 1,
      guidanceHistory: [
        LifeMateCompanionGuidanceHistoryItem(
          guidanceId: 'energy.give_space',
          shownAtUtc: now.subtract(const Duration(hours: 24)),
        ),
      ],
      supportActions: const [],
      locale: 'en',
      nowUtc: now,
    );
    expect(result?.id, 'general.ask_first');
  });

  test('recent support action is reused to avoid repetitive advice', () {
    final result = engine.select(
      phaseAllowed: false,
      wellbeingAllowed: true,
      cycleDay: null,
      mood: 'neutral',
      energyLevel: 1,
      guidanceHistory: const [],
      supportActions: [
        LifeMateCompanionSupportActionHistoryItem(
          actionType: 'Chores',
          performedAtUtc: now.subtract(const Duration(hours: 12)),
        ),
      ],
      locale: 'en',
      nowUtc: now,
    );
    expect(result?.id, 'general.ask_first');
  });
}
