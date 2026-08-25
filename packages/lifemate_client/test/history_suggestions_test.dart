import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test('normalizes Persian/Arabic letters, ZWNJ and localized digits', () {
    expect(
      normalizeLifeMateHistoryText('  دكتر\u200cعلي ۱۲٣  '),
      'دکتر علی 123',
    );
  });

  test('requires at least two normalized query characters', () {
    final history = [
      LifeMateHistoryUsage(
        kind: LifeMateHistorySuggestionKind.doctor,
        value: 'دکتر سارا راد',
        usedAt: DateTime.utc(2026, 8, 20),
      ),
    ];
    expect(
      rankLifeMateHistorySuggestions(
        history: history,
        query: 'س',
        kind: LifeMateHistorySuggestionKind.doctor,
      ),
      isEmpty,
    );
  });

  test('ranking is deterministic, context-scoped, recent then frequent', () {
    final history = <LifeMateHistoryUsage>[
      LifeMateHistoryUsage(
        kind: LifeMateHistorySuggestionKind.doctor,
        value: 'دکتر سارا راد',
        usedAt: DateTime.utc(2026, 8, 20),
        context: 'قلب',
      ),
      LifeMateHistoryUsage(
        kind: LifeMateHistorySuggestionKind.doctor,
        value: 'دكتر سارا راد',
        usedAt: DateTime.utc(2026, 8, 1),
        context: 'قلب',
      ),
      LifeMateHistoryUsage(
        kind: LifeMateHistorySuggestionKind.doctor,
        value: 'سارا محمدی',
        usedAt: DateTime.utc(2026, 8, 23),
      ),
      LifeMateHistoryUsage(
        kind: LifeMateHistorySuggestionKind.center,
        value: 'کلینیک سارا',
        usedAt: DateTime.utc(2026, 8, 24),
      ),
    ];

    final values = rankLifeMateHistorySuggestions(
      history: history,
      query: 'سارا',
      kind: LifeMateHistorySuggestionKind.doctor,
    );

    expect(values.map((item) => item.value), ['سارا محمدی', 'دکتر سارا راد']);
    expect(values.last.usageCount, 2);
    expect(values.every((item) => item.kind == LifeMateHistorySuggestionKind.doctor), isTrue);
  });

  test('prefix matches rank above contains matches before recency', () {
    final history = <LifeMateHistoryUsage>[
      LifeMateHistoryUsage(
        kind: LifeMateHistorySuggestionKind.medication,
        value: 'ویتامین D',
        usedAt: DateTime.utc(2026, 8, 24),
      ),
      LifeMateHistoryUsage(
        kind: LifeMateHistorySuggestionKind.medication,
        value: 'D-Vitamin',
        usedAt: DateTime.utc(2026, 8, 25),
      ),
    ];

    final values = rankLifeMateHistorySuggestions(
      history: history,
      query: 'ویت',
      kind: LifeMateHistorySuggestionKind.medication,
    );

    expect(values.single.value, 'ویتامین D');
  });
}
