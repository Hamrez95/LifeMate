import 'package:cocoonmate_module/clinical/clinical_content.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final activeTime = DateTime.utc(2026, 10, 1);

  test('weekly content maps deterministically without mutable current week',
      () {
    final selection = bundledPregnancyClinicalContent.weekly(
      gestationalWeek: 4,
      locale: 'fa',
      atUtc: activeTime,
    );
    expect(selection.content.key, 'pregnancy.week.4.summary');
    expect(selection.content.gestationalWeek, 4);
    expect(selection.content.locale, 'fa');
    expect(selection.usedLocaleFallback, isFalse);
    expect(selection.usedSafetyFallback, isFalse);
  });

  test('missing week uses approved fallback rather than invented content', () {
    final selection = bundledPregnancyClinicalContent.weekly(
      gestationalWeek: 42,
      locale: 'fa',
      atUtc: activeTime,
    );
    expect(selection.content.key, 'pregnancy.content.unavailable');
    expect(selection.usedSafetyFallback, isTrue);
  });

  test('unsupported locale falls back to approved English content', () {
    final selection = bundledPregnancyClinicalContent.weekly(
      gestationalWeek: 4,
      locale: 'de',
      atUtc: activeTime,
    );
    expect(selection.content.locale, 'en');
    expect(selection.usedLocaleFallback, isTrue);
  });

  test('out-of-range gestational week uses approved fallback', () {
    final selection = bundledPregnancyClinicalContent.weekly(
      gestationalWeek: 0,
      locale: 'en',
      atUtc: activeTime,
    );
    expect(selection.usedSafetyFallback, isTrue);
  });

  test('expired content cannot be selected as current guidance', () {
    final expired = PregnancyClinicalContentRegistry([
      PregnancyClinicalContent(
        key: 'pregnancy.week.4.summary',
        version: 99,
        locale: 'en',
        contentClass: ClinicalContentClass.weeklyEducation,
        severity: ClinicalSeverity.informational,
        status: ClinicalContentStatus.published,
        review: ClinicalReviewMetadata(
          reviewedByRef: 'test-review',
          reviewedAtUtc: DateTime.utc(2025),
          reviewDueAtUtc: DateTime.utc(2026),
          sourceReferences: const ['test-source'],
        ),
        gestationalWeek: 4,
        title: 'Expired',
        body: 'Expired',
      ),
      bundledPregnancyClinicalContent.entries.firstWhere(
        (entry) =>
            entry.key == 'pregnancy.content.unavailable' &&
            entry.locale == 'en',
      ),
    ]);
    final selection = expired.weekly(
      gestationalWeek: 4,
      locale: 'en',
      atUtc: activeTime,
    );
    expect(selection.content.key, 'pregnancy.content.unavailable');
  });

  test('bounded emergency signals deterministically escalate', () {
    final decision = bundledPregnancySafetyRules.evaluate(
      signals: const {PregnancySafetySignal.heavyBleeding},
      atUtc: activeTime,
    );
    expect(decision.ruleSetVersion, 1);
    expect(decision.outcome, PregnancySafetyOutcome.emergency);
    expect(
      decision.guidanceKey,
      'pregnancy.safety.seek_emergency_care',
    );
  });

  test('unsupported safety input fails to conservative guidance', () {
    final decision = bundledPregnancySafetyRules.evaluate(
      signals: const {PregnancySafetySignal.unsupported},
      atUtc: activeTime,
    );
    expect(decision.outcome, PregnancySafetyOutcome.conservativeFallback);
    expect(decision.guidanceKey, 'pregnancy.safety.conservative_fallback');
  });

  test('disabled safety rules never silently return normal guidance', () {
    final rules = PregnancySafetyRuleSet(
      version: 2,
      status: ClinicalContentStatus.disabled,
      review: bundledPregnancySafetyRules.review,
    );
    final decision = rules.evaluate(
      signals: const {PregnancySafetySignal.heavyBleeding},
      atUtc: activeTime,
    );
    expect(decision.outcome, PregnancySafetyOutcome.conservativeFallback);
  });

  test('clinical registry and rule engine have no LLM dependency surface', () {
    final diagnostics = [
      ...bundledPregnancyClinicalContent.entries.map((entry) => entry.key),
      bundledPregnancySafetyRules.version.toString(),
    ].join(' ');
    expect(diagnostics.toLowerCase(), isNot(contains('llm')));
    expect(diagnostics.toLowerCase(), isNot(contains('openai')));
  });
}
