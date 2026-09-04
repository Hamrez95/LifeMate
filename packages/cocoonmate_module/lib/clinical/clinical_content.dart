enum ClinicalContentClass {
  weeklyEducation,
  routineSelfCare,
  appointmentInformation,
  redFlagSafety,
  legalEmergency,
}

enum ClinicalContentStatus { draft, published, disabled }

enum ClinicalSeverity { informational, caution, urgent, emergency }

class ClinicalReviewMetadata {
  const ClinicalReviewMetadata({
    required this.reviewedByRef,
    required this.reviewedAtUtc,
    required this.reviewDueAtUtc,
    required this.sourceReferences,
  });

  final String reviewedByRef;
  final DateTime reviewedAtUtc;
  final DateTime reviewDueAtUtc;
  final List<String> sourceReferences;

  bool isExpired(DateTime atUtc) => !atUtc.isBefore(reviewDueAtUtc);
}

class PregnancyClinicalContent {
  const PregnancyClinicalContent({
    required this.key,
    required this.version,
    required this.locale,
    required this.contentClass,
    required this.severity,
    required this.status,
    required this.review,
    required this.title,
    required this.body,
    this.gestationalWeek,
    this.jurisdiction = 'global',
  });

  final String key;
  final int version;
  final String locale;
  final String jurisdiction;
  final ClinicalContentClass contentClass;
  final ClinicalSeverity severity;
  final ClinicalContentStatus status;
  final ClinicalReviewMetadata review;
  final int? gestationalWeek;
  final String title;
  final String body;

  bool isUsableAt(DateTime atUtc) =>
      status == ClinicalContentStatus.published && !review.isExpired(atUtc);
}

class ClinicalContentSelection {
  const ClinicalContentSelection({
    required this.content,
    required this.usedLocaleFallback,
    required this.usedSafetyFallback,
  });

  final PregnancyClinicalContent content;
  final bool usedLocaleFallback;
  final bool usedSafetyFallback;
}

class PregnancyClinicalContentRegistry {
  const PregnancyClinicalContentRegistry(this.entries);

  final List<PregnancyClinicalContent> entries;

  ClinicalContentSelection weekly({
    required int gestationalWeek,
    required String locale,
    required DateTime atUtc,
  }) {
    if (gestationalWeek < 1 || gestationalWeek > 42) {
      return _fallback(locale: locale, atUtc: atUtc);
    }

    PregnancyClinicalContent? select(String candidateLocale) {
      final matches = entries.where(
        (entry) =>
            entry.contentClass == ClinicalContentClass.weeklyEducation &&
            entry.gestationalWeek == gestationalWeek &&
            entry.locale == candidateLocale &&
            entry.isUsableAt(atUtc),
      );
      if (matches.isEmpty) return null;
      final sorted = matches.toList()
        ..sort((a, b) => b.version.compareTo(a.version));
      return sorted.first;
    }

    final exact = select(locale);
    if (exact != null) {
      return ClinicalContentSelection(
        content: exact,
        usedLocaleFallback: false,
        usedSafetyFallback: false,
      );
    }

    final english = select('en');
    if (english != null) {
      return ClinicalContentSelection(
        content: english,
        usedLocaleFallback: true,
        usedSafetyFallback: false,
      );
    }

    return _fallback(locale: locale, atUtc: atUtc);
  }

  ClinicalContentSelection _fallback({
    required String locale,
    required DateTime atUtc,
  }) {
    final candidates = entries.where(
      (entry) =>
          entry.key == 'pregnancy.content.unavailable' &&
          entry.isUsableAt(atUtc) &&
          (entry.locale == locale || entry.locale == 'en'),
    );
    if (candidates.isEmpty) {
      throw StateError('No approved pregnancy content fallback is available.');
    }
    final sorted = candidates.toList()
      ..sort((a, b) {
        final localeScoreA = a.locale == locale ? 1 : 0;
        final localeScoreB = b.locale == locale ? 1 : 0;
        final localeOrder = localeScoreB.compareTo(localeScoreA);
        return localeOrder != 0
            ? localeOrder
            : b.version.compareTo(a.version);
      });
    return ClinicalContentSelection(
      content: sorted.first,
      usedLocaleFallback: sorted.first.locale != locale,
      usedSafetyFallback: true,
    );
  }
}

enum PregnancySafetySignal {
  heavyBleeding,
  lossOfConsciousness,
  severeBreathingDifficulty,
  severeChestPain,
  unsupported,
}

enum PregnancySafetyOutcome { emergency, urgentReview, conservativeFallback }

class PregnancySafetyDecision {
  const PregnancySafetyDecision({
    required this.ruleSetVersion,
    required this.outcome,
    required this.guidanceKey,
  });

  final int ruleSetVersion;
  final PregnancySafetyOutcome outcome;
  final String guidanceKey;
}

class PregnancySafetyRuleSet {
  const PregnancySafetyRuleSet({
    required this.version,
    required this.status,
    required this.review,
  });

  final int version;
  final ClinicalContentStatus status;
  final ClinicalReviewMetadata review;

  PregnancySafetyDecision evaluate({
    required Set<PregnancySafetySignal> signals,
    required DateTime atUtc,
  }) {
    if (status != ClinicalContentStatus.published || review.isExpired(atUtc)) {
      return _fallback();
    }

    const emergencySignals = {
      PregnancySafetySignal.heavyBleeding,
      PregnancySafetySignal.lossOfConsciousness,
      PregnancySafetySignal.severeBreathingDifficulty,
      PregnancySafetySignal.severeChestPain,
    };
    if (signals.any(emergencySignals.contains)) {
      return PregnancySafetyDecision(
        ruleSetVersion: version,
        outcome: PregnancySafetyOutcome.emergency,
        guidanceKey: 'pregnancy.safety.seek_emergency_care',
      );
    }

    if (signals.isEmpty || signals.contains(PregnancySafetySignal.unsupported)) {
      return _fallback();
    }

    return PregnancySafetyDecision(
      ruleSetVersion: version,
      outcome: PregnancySafetyOutcome.urgentReview,
      guidanceKey: 'pregnancy.safety.contact_clinician',
    );
  }

  PregnancySafetyDecision _fallback() => PregnancySafetyDecision(
        ruleSetVersion: version,
        outcome: PregnancySafetyOutcome.conservativeFallback,
        guidanceKey: 'pregnancy.safety.conservative_fallback',
      );
}

final DateTime _reviewedAt = DateTime.utc(2026, 9, 4);
final DateTime _reviewDueAt = DateTime.utc(2027, 3, 4);

ClinicalReviewMetadata _review(List<String> sources) => ClinicalReviewMetadata(
      reviewedByRef: 'clinical-review/pregnancy-foundation-v1',
      reviewedAtUtc: _reviewedAt,
      reviewDueAtUtc: _reviewDueAt,
      sourceReferences: sources,
    );

final PregnancyClinicalContentRegistry bundledPregnancyClinicalContent =
    PregnancyClinicalContentRegistry([
  PregnancyClinicalContent(
    key: 'pregnancy.week.4.summary',
    version: 1,
    locale: 'en',
    contentClass: ClinicalContentClass.weeklyEducation,
    severity: ClinicalSeverity.informational,
    status: ClinicalContentStatus.published,
    review: _review(['internal-clinical-review-v1']),
    gestationalWeek: 4,
    title: 'Week 4',
    body:
        'Early pregnancy changes vary. Use your care plan and contact your clinician if you have concerns.',
  ),
  PregnancyClinicalContent(
    key: 'pregnancy.week.4.summary',
    version: 1,
    locale: 'fa',
    contentClass: ClinicalContentClass.weeklyEducation,
    severity: ClinicalSeverity.informational,
    status: ClinicalContentStatus.published,
    review: _review(['internal-clinical-review-v1']),
    gestationalWeek: 4,
    title: 'هفته ۴',
    body:
        'تغییرات اوایل بارداری در افراد متفاوت است. برنامه مراقبتی خود را دنبال کنید و در صورت نگرانی با پزشک یا ماما تماس بگیرید.',
  ),
  PregnancyClinicalContent(
    key: 'pregnancy.content.unavailable',
    version: 1,
    locale: 'en',
    contentClass: ClinicalContentClass.legalEmergency,
    severity: ClinicalSeverity.caution,
    status: ClinicalContentStatus.published,
    review: _review(['internal-clinical-review-v1']),
    title: 'Content temporarily unavailable',
    body:
        'Approved pregnancy guidance is unavailable. Use your existing care plan and seek professional care for urgent concerns.',
  ),
  PregnancyClinicalContent(
    key: 'pregnancy.content.unavailable',
    version: 1,
    locale: 'fa',
    contentClass: ClinicalContentClass.legalEmergency,
    severity: ClinicalSeverity.caution,
    status: ClinicalContentStatus.published,
    review: _review(['internal-clinical-review-v1']),
    title: 'محتوای تأییدشده موقتاً در دسترس نیست',
    body:
        'تا زمان دسترسی دوباره به راهنمای تأییدشده، برنامه مراقبتی فعلی خود را دنبال کنید و برای نگرانی‌های فوری از مراقبت حرفه‌ای استفاده کنید.',
  ),
]);

final PregnancySafetyRuleSet bundledPregnancySafetyRules =
    PregnancySafetyRuleSet(
  version: 1,
  status: ClinicalContentStatus.published,
  review: _review(['internal-clinical-review-v1']),
);
