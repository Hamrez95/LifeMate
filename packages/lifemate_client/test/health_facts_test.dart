import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test('account preparation has at least 100 unique health facts', () {
    expect(lifeMateHealthFacts.length, greaterThanOrEqualTo(100));
    expect(
      lifeMateHealthFacts.map((fact) => fact.text).toSet().length,
      lifeMateHealthFacts.length,
    );
  });

  test('health facts are categorized and non-diagnostic', () {
    expect(
      lifeMateHealthFacts.every(
        (fact) => fact.category.trim().isNotEmpty && fact.text.trim().isNotEmpty,
      ),
      isTrue,
    );
    expect(
      lifeMateHealthFacts.map((fact) => fact.category).toSet().length,
      greaterThanOrEqualTo(8),
    );
  });
}
