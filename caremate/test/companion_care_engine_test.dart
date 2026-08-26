import 'package:flutter_test/flutter_test.dart';

import 'package:caremate/services/companion_care_engine.dart';

void main() {
  const engine = CompanionCareEngine();
  final now = DateTime.utc(2026, 8, 26, 16);

  test('revoke or share-off makes personalized guidance ineligible', () {
    final guidance = engine.select(
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

    expect(guidance, isNull);
  });

  test('low shared energy selects non-diagnostic support copy', () {
    final guidance = engine.select(
      phaseAllowed: false,
      wellbeingAllowed: true,
      cycleDay: null,
      mood: 'good',
      energyLevel: 2,
      guidanceHistory: const [],
      supportActions: const [],
      locale: 'en',
      nowUtc: now,
    );

    expect(guidance?.category, 'energy');
    expect(guidance?.supportActionType, 'chores');
    expect(guidance?.contentVersion, CompanionCareEngine.contentVersion);
    expect(guidance?.message.toLowerCase(), isNot(contains('diagnos')));
    expect(guidance?.message.toLowerCase(), isNot(contains('treat')));
  });

  test('global cooldown suppresses another guidance impression', () {
    final guidance = engine.select(
      phaseAllowed: true,
      wellbeingAllowed: true,
      cycleDay: 12,
      mood: 'good',
      energyLevel: 4,
      guidanceHistory: [
        CompanionGuidanceHistoryItem(
          guidanceId: 'general.ask_first',
          shownAtUtc: now.subtract(const Duration(hours: 3)),
        ),
      ],
      supportActions: const [],
      locale: 'fa',
      nowUtc: now,
    );

    expect(guidance, isNull);
  });

  test('recent support action prevents repetitive suggestion', () {
    final guidance = engine.select(
      phaseAllowed: false,
      wellbeingAllowed: true,
      cycleDay: null,
      mood: 'good',
      energyLevel: 1,
      guidanceHistory: const [],
      supportActions: [
        CompanionSupportActionHistoryItem(
          actionType: 'chores',
          performedAtUtc: now.subtract(const Duration(hours: 4)),
        ),
      ],
      locale: 'en',
      nowUtc: now,
    );

    expect(guidance, isNull);
  });

  test('CheckIn server spelling deduplicates check-in guidance', () {
    final guidance = engine.select(
      phaseAllowed: true,
      wellbeingAllowed: false,
      cycleDay: 8,
      mood: null,
      energyLevel: null,
      guidanceHistory: const [],
      supportActions: [
        CompanionSupportActionHistoryItem(
          actionType: 'checkin',
          performedAtUtc: now.subtract(const Duration(hours: 2)),
        ),
      ],
      locale: 'en',
      nowUtc: now,
    );

    expect(guidance, isNull);
  });

  test('content is locale-aware with stable identifiers', () {
    final fa = engine.select(
      phaseAllowed: false,
      wellbeingAllowed: true,
      cycleDay: null,
      mood: 'good',
      energyLevel: 5,
      guidanceHistory: const [],
      supportActions: const [],
      locale: 'fa-IR',
      nowUtc: now,
    );
    final en = engine.select(
      phaseAllowed: false,
      wellbeingAllowed: true,
      cycleDay: null,
      mood: 'good',
      energyLevel: 5,
      guidanceHistory: const [],
      supportActions: const [],
      locale: 'en-US',
      nowUtc: now,
    );

    expect(fa?.id, en?.id);
    expect(fa?.contentVersion, en?.contentVersion);
    expect(fa?.locale, 'fa');
    expect(en?.locale, 'en');
    expect(fa?.message, isNot(en?.message));
  });
}
