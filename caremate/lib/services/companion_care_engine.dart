/// Versioned, non-diagnostic companion guidance selection for #105.
///
/// This deliberately accepts only the already-authorized, field-level summary
/// returned to CareMate. Private notes and unshared health details are not part
/// of this contract.
class CompanionCareGuidance {
  const CompanionCareGuidance({
    required this.id,
    required this.category,
    required this.locale,
    required this.message,
  });
  final String id;
  final String category;
  final String locale;
  final String message;
}

class CompanionCareEngine {
  static const version = 'companion-care-v1';

  CompanionCareGuidance? select({
    required bool phaseAllowed,
    required bool wellbeingAllowed,
    required int? cycleDay,
    required String? mood,
    required int? energyLevel,
    required Set<String> recentlyShownIds,
    required String locale,
  }) {
    final fa = locale.toLowerCase().startsWith('fa');
    final candidates = <CompanionCareGuidance>[
      if (wellbeingAllowed && (energyLevel != null && energyLevel <= 2))
        CompanionCareGuidance(
          id: 'low-energy-v1',
          category: 'energy',
          locale: fa ? 'fa' : 'en',
          message: fa
              ? 'اگر حالش مناسب بود، شاید کمک در کارهای روزمره یا کمی استراحت براش خوشایند باشد.'
              : 'If it feels welcome, offering help with everyday tasks or a little rest may be kind.',
        ),
      if (wellbeingAllowed && mood?.toLowerCase() == 'low')
        CompanionCareGuidance(
          id: 'gentle-check-in-v1',
          category: 'mood',
          locale: fa ? 'fa' : 'en',
          message: fa
              ? 'گاهی فقط پرسیدنِ «امروز چطوری؟» بهترین همراهی است.'
              : 'Sometimes a gentle “How are you today?” is the most helpful support.',
        ),
      if (phaseAllowed && cycleDay != null)
        CompanionCareGuidance(
          id: 'phase-kindness-v1',
          category: 'phase',
          locale: fa ? 'fa' : 'en',
          message: fa
              ? 'وضعیت چرخه فقط تقریبی است؛ اگر مناسب بود، یک پیشنهاد ساده برای استراحت یا نوشیدنی گرم می‌تواند مهربانانه باشد.'
              : 'The cycle status is only an estimate; if welcome, a simple offer of rest or a warm drink can be kind.',
        ),
    ];
    for (final candidate in candidates) {
      if (!recentlyShownIds.contains(candidate.id)) return candidate;
    }
    return null;
  }
}
