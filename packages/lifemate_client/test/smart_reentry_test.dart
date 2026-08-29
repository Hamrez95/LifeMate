import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  final now = DateTime(2026, 8, 29);

  SmartReentryHistoryItem visit(DateTime date, {bool recurring = false}) =>
      SmartReentryHistoryItem(
        id: date.toIso8601String(),
        kind: SmartReentryKind.appointment,
        occurredOn: date,
        identityKey: 'دکتر سارا راد|کلینیک امید',
        source: const {
          'eventType': 'appointment',
          'title': 'ویزیت',
          'providerName': 'دکتر سارا راد',
          'centerName': 'کلینیک امید',
        },
        hasActiveRecurrence: recurring,
      );

  test('stable user history creates one explainable suggestion', () {
    final result = detectSmartReentrySuggestions(
      now: now,
      history: [
        visit(DateTime(2026, 2, 28)),
        visit(DateTime(2026, 4, 28)),
        visit(DateTime(2026, 6, 28)),
      ],
    );
    expect(result, hasLength(1));
    expect(result.single.kind, SmartReentryKind.appointment);
    expect(result.single.averageIntervalDays, inInclusiveRange(59, 62));
    expect(result.single.reasonDaysAgo, inInclusiveRange(61, 63));
  });

  test('insufficient or unstable evidence fails closed', () {
    expect(
      detectSmartReentrySuggestions(
        now: now,
        history: [
          visit(DateTime(2026, 4, 28)),
          visit(DateTime(2026, 6, 28)),
        ],
      ),
      isEmpty,
    );
    expect(
      detectSmartReentrySuggestions(
        now: now,
        history: [
          visit(DateTime(2026, 1, 1)),
          visit(DateTime(2026, 2, 1)),
          visit(DateTime(2026, 6, 28)),
        ],
      ),
      isEmpty,
    );
  });

  test('active recurrence and newer matching record suppress duplicates', () {
    final history = [
      visit(DateTime(2026, 2, 28)),
      visit(DateTime(2026, 4, 28)),
      visit(DateTime(2026, 6, 28), recurring: true),
    ];
    expect(detectSmartReentrySuggestions(now: now, history: history), isEmpty);

    final nonRecurring = [
      visit(DateTime(2026, 2, 28)),
      visit(DateTime(2026, 4, 28)),
      visit(DateTime(2026, 6, 28)),
    ];
    final candidate = detectSmartReentrySuggestions(
      now: now,
      history: nonRecurring,
    ).single;
    expect(
      detectSmartReentrySuggestions(
        now: now,
        history: nonRecurring,
        existingPatternKeys: {candidate.patternKey},
      ),
      isEmpty,
    );
  });

  test('dismissal cooldown and permanent mute block matching pattern', () {
    final history = [
      visit(DateTime(2026, 2, 28)),
      visit(DateTime(2026, 4, 28)),
      visit(DateTime(2026, 6, 28)),
    ];
    final key = detectSmartReentrySuggestions(now: now, history: history)
        .single
        .patternKey;
    expect(
      detectSmartReentrySuggestions(
        now: now,
        history: history,
        suppressions: [
          SmartReentrySuppression(
            patternKey: key,
            dismissedUntil: now.add(const Duration(days: 30)),
          ),
        ],
      ),
      isEmpty,
    );
    expect(
      detectSmartReentrySuggestions(
        now: now,
        history: history,
        suppressions: [
          SmartReentrySuppression(patternKey: key, permanentlyMuted: true),
        ],
      ),
      isEmpty,
    );
  });

  test('ended recurrence is not treated as active', () {
    expect(
      smartReentryRecurrenceIsActive(
        {
          'enabled': true,
          'unit': 'month',
          'interval': 1,
          'endDate': '2026-07-01',
        },
        now: now,
      ),
      isFalse,
    );
    expect(
      smartReentryRecurrenceIsActive(
        {'enabled': true, 'unit': 'month', 'interval': 1},
        now: now,
      ),
      isTrue,
    );
  });

  test('suggestion count is capped', () {
    final history = <SmartReentryHistoryItem>[];
    for (final key in ['A', 'B', 'C']) {
      for (final date in [
        DateTime(2026, 2, 28),
        DateTime(2026, 4, 28),
        DateTime(2026, 6, 28),
      ]) {
        history.add(SmartReentryHistoryItem(
          id: '$key-$date',
          kind: SmartReentryKind.appointment,
          occurredOn: date,
          identityKey: key,
          source: {'title': key},
        ));
      }
    }
    expect(
      detectSmartReentrySuggestions(now: now, history: history, limit: 2),
      hasLength(2),
    );
  });
}
