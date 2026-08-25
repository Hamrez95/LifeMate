import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test('suggestion selection contract never mutates source history', () {
    final history = <LifeMateHistoryUsage>[
      LifeMateHistoryUsage(
        kind: LifeMateHistorySuggestionKind.doctor,
        value: 'دکتر سارا راد',
        usedAt: DateTime.utc(2026, 8, 20),
      ),
    ];

    final suggestions = rankLifeMateHistorySuggestions(
      history: history,
      query: 'سارا',
      kind: LifeMateHistorySuggestionKind.doctor,
    );

    expect(suggestions.single.value, 'دکتر سارا راد');
    expect(history.single.value, 'دکتر سارا راد');
  });

  test('suggestions stay field-scoped for medication vs doctor', () {
    final history = <LifeMateHistoryUsage>[
      LifeMateHistoryUsage(
        kind: LifeMateHistorySuggestionKind.medication,
        value: 'Cetirizine',
        usedAt: DateTime.utc(2026, 8, 20),
      ),
      LifeMateHistoryUsage(
        kind: LifeMateHistorySuggestionKind.doctor,
        value: 'Dr Cetirizine',
        usedAt: DateTime.utc(2026, 8, 21),
      ),
    ];

    final medication = rankLifeMateHistorySuggestions(
      history: history,
      query: 'ceti',
      kind: LifeMateHistorySuggestionKind.medication,
    );
    expect(medication.map((item) => item.value), ['Cetirizine']);
  });
}
