class LifeMateCompanionPhaseNotificationHistoryItem {
  const LifeMateCompanionPhaseNotificationHistoryItem({
    required this.guidanceId,
    required this.shownAtUtc,
  });

  final String guidanceId;
  final DateTime shownAtUtc;
}

class LifeMateCompanionPhaseNotification {
  const LifeMateCompanionPhaseNotification({
    required this.guidanceId,
    required this.contentVersion,
    required this.title,
    required this.fullBody,
    required this.privateBody,
    required this.isPrediction,
  });

  final String guidanceId;
  final String contentVersion;
  final String title;
  final String fullBody;
  final String privateBody;
  final bool isPrediction;
}

class LifeMateCompanionPhaseNotificationEngine {
  const LifeMateCompanionPhaseNotificationEngine();

  static const contentVersion = 'companion-phase-notifications-v1';
  static const _cadence = Duration(hours: 24);

  LifeMateCompanionPhaseNotification? select({
    required bool receivePhaseNotifications,
    required bool viewPhaseSummary,
    required bool viewPeriodTiming,
    required bool caregiverNotificationsEnabled,
    required String? cycleStart,
    required int? cycleDay,
    required String? detailedPhase,
    required int? daysUntilNextPeriod,
    required String? nextPeriodStart,
    required String? confidence,
    required String? cyclePattern,
    required List<LifeMateCompanionPhaseNotificationHistoryItem> history,
    required String locale,
    required DateTime nowUtc,
  }) {
    if (!receivePhaseNotifications ||
        !viewPhaseSummary ||
        !caregiverNotificationsEnabled) {
      return null;
    }

    final normalizedCycleStart = _date(cycleStart);
    if (normalizedCycleStart == null || cycleDay == null || cycleDay < 1) {
      return null;
    }

    final now = nowUtc.toUtc();
    if (history.any(
      (item) =>
          item.guidanceId.startsWith('notify.phase.') &&
          now.difference(item.shownAtUtc.toUtc()) >= Duration.zero &&
          now.difference(item.shownAtUtc.toUtc()) < _cadence,
    )) {
      return null;
    }

    final language = locale.toLowerCase().startsWith('fa') ? 'fa' : 'en';
    final phase = detailedPhase?.trim().toLowerCase() ?? '';
    final confidenceValue = confidence?.trim().toLowerCase() ?? 'low';
    final pattern = cyclePattern?.trim().toLowerCase() ?? 'insufficient_data';

    // A recorded cycle start is factual timing data. It may be used only when
    // its independent timing scope is present; low prediction confidence does
    // not make the recorded event itself uncertain.
    if (cycleDay == 1 && viewPeriodTiming) {
      final candidate = _periodStart(language, normalizedCycleStart);
      return _deduplicated(candidate, history);
    }

    // Never turn low-confidence/irregular data into phase claims. Fertility and
    // ovulation communication belongs exclusively to #108 and is excluded here.
    if (confidenceValue == 'low' ||
        pattern == 'variable' ||
        pattern == 'insufficient_data' ||
        phase == 'fertile' ||
        phase == 'ovulation') {
      return null;
    }

    if (daysUntilNextPeriod != null &&
        daysUntilNextPeriod >= 0 &&
        daysUntilNextPeriod <= 2 &&
        _date(nextPeriodStart) != null) {
      final candidate = _approachingPeriod(
        language,
        normalizedCycleStart,
        _date(nextPeriodStart)!,
      );
      return _deduplicated(candidate, history);
    }

    if (phase == 'follicular' || phase == 'luteal' || phase == 'pms') {
      final candidate = _phase(language, normalizedCycleStart, phase);
      return _deduplicated(candidate, history);
    }

    return null;
  }

  LifeMateCompanionPhaseNotification? _deduplicated(
    LifeMateCompanionPhaseNotification candidate,
    List<LifeMateCompanionPhaseNotificationHistoryItem> history,
  ) => history.any((item) => item.guidanceId == candidate.guidanceId)
      ? null
      : candidate;

  LifeMateCompanionPhaseNotification _periodStart(
    String language,
    String cycleStart,
  ) => LifeMateCompanionPhaseNotification(
    guidanceId: 'notify.phase.period_start.$cycleStart',
    contentVersion: contentVersion,
    title: language == 'fa' ? 'یک همراهی آرام' : 'A gentle moment to support',
    fullBody: language == 'fa'
        ? 'شروع دوره ثبت شده است. بدون پیش‌فرض درباره حال او، می‌توانی بپرسی امروز چه نوع همراهی‌ای برایش بهتر است.'
        : 'A period start was recorded. Without assuming how your partner feels, you can ask what kind of support would be useful today.',
    privateBody: language == 'fa'
        ? 'یک به‌روزرسانی خصوصی در CareMate داری. برای جزئیات، اپ را باز کن.'
        : 'You have a private CareMate update. Open the app for details.',
    isPrediction: false,
  );

  LifeMateCompanionPhaseNotification _approachingPeriod(
    String language,
    String cycleStart,
    String nextPeriod,
  ) => LifeMateCompanionPhaseNotification(
    guidanceId: 'notify.phase.period_approach.$cycleStart.$nextPeriod',
    contentVersion: contentVersion,
    title: language == 'fa' ? 'بر اساس اطلاعات چرخه' : 'Based on cycle information',
    fullBody: language == 'fa'
        ? 'بر اساس اطلاعات چرخه، ممکن است دوره بعدی نزدیک باشد. این فقط یک برآورد است؛ همراهی را با پرسیدن و بدون پیش‌فرض شروع کن.'
        : 'Based on cycle information, the next period may be approaching. This is only an estimate; start with asking, not assuming.',
    privateBody: language == 'fa'
        ? 'یک به‌روزرسانی خصوصی در CareMate داری. برای جزئیات، اپ را باز کن.'
        : 'You have a private CareMate update. Open the app for details.',
    isPrediction: true,
  );

  LifeMateCompanionPhaseNotification _phase(
    String language,
    String cycleStart,
    String phase,
  ) => LifeMateCompanionPhaseNotification(
    guidanceId: 'notify.phase.$phase.$cycleStart',
    contentVersion: contentVersion,
    title: language == 'fa' ? 'یک یادآوری حمایتی' : 'A supportive reminder',
    fullBody: language == 'fa'
        ? 'بر اساس اطلاعات چرخه، فاز فعلی به‌صورت تقریبی تغییر کرده است. این به معنی پیش‌بینی حال او نیست؛ اگر می‌خواهی کمک کنی، اول بپرس.'
        : 'Based on cycle information, the estimated phase has changed. This does not predict how your partner feels; ask first if you want to help.',
    privateBody: language == 'fa'
        ? 'یک به‌روزرسانی خصوصی در CareMate داری. برای جزئیات، اپ را باز کن.'
        : 'You have a private CareMate update. Open the app for details.',
    isPrediction: true,
  );

  static String? _date(String? value) {
    final text = value?.trim() ?? '';
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) return null;
    final parsed = DateTime.tryParse('${text}T00:00:00Z');
    return parsed == null || parsed.toIso8601String().substring(0, 10) != text
        ? null
        : text;
  }
}
