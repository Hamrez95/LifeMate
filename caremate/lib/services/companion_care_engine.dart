class CompanionGuidanceHistoryItem {
  const CompanionGuidanceHistoryItem({
    required this.guidanceId,
    required this.shownAtUtc,
  });

  final String guidanceId;
  final DateTime shownAtUtc;
}

class CompanionSupportActionHistoryItem {
  const CompanionSupportActionHistoryItem({
    required this.actionType,
    required this.performedAtUtc,
  });

  final String actionType;
  final DateTime performedAtUtc;
}

class CompanionCareGuidance {
  const CompanionCareGuidance({
    required this.id,
    required this.category,
    required this.contentVersion,
    required this.locale,
    required this.title,
    required this.message,
    required this.cooldown,
    this.supportActionType,
    this.supportActionLabel,
  });

  final String id;
  final String category;
  final String contentVersion;
  final String locale;
  final String title;
  final String message;
  final Duration cooldown;
  final String? supportActionType;
  final String? supportActionLabel;
}

class CompanionCareEngine {
  const CompanionCareEngine();

  static const contentVersion = 'companion-care-v1';
  static const _globalCooldown = Duration(hours: 18);
  static const _actionCooldown = Duration(hours: 36);

  CompanionCareGuidance? select({
    required bool phaseAllowed,
    required bool wellbeingAllowed,
    required int? cycleDay,
    required String? mood,
    required int? energyLevel,
    required List<CompanionGuidanceHistoryItem> guidanceHistory,
    required List<CompanionSupportActionHistoryItem> supportActions,
    required String locale,
    required DateTime nowUtc,
  }) {
    if (!phaseAllowed && !wellbeingAllowed) return null;
    final now = nowUtc.toUtc();
    if (guidanceHistory.any(
      (item) => now.difference(item.shownAtUtc.toUtc()) < _globalCooldown,
    )) {
      return null;
    }

    final language = locale.toLowerCase().startsWith('fa') ? 'fa' : 'en';
    final candidates = <CompanionCareGuidance>[];
    if (wellbeingAllowed && energyLevel != null && energyLevel <= 2) {
      candidates.add(_lowEnergy(language));
    }
    final normalizedMood = mood?.trim().toLowerCase();
    if (wellbeingAllowed &&
        (normalizedMood == 'low' || normalizedMood == 'overwhelmed')) {
      candidates.add(_gentleCheckIn(language));
    }
    if (phaseAllowed && cycleDay != null && cycleDay > 0) {
      candidates.add(_phaseAware(language));
    }
    if (candidates.isEmpty) candidates.add(_general(language));

    for (final candidate in candidates) {
      final recentlyShown = guidanceHistory.any(
        (item) =>
            item.guidanceId == candidate.id &&
            now.difference(item.shownAtUtc.toUtc()) < candidate.cooldown,
      );
      if (recentlyShown) continue;
      final action = candidate.supportActionType;
      if (action != null &&
          supportActions.any(
            (item) =>
                _normalizeAction(item.actionType) == action &&
                now.difference(item.performedAtUtc.toUtc()) < _actionCooldown,
          )) {
        continue;
      }
      return candidate;
    }
    return null;
  }

  static String _normalizeAction(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll('checkin', 'check_in');

  CompanionCareGuidance _lowEnergy(String locale) => CompanionCareGuidance(
    id: 'energy.give_space',
    category: 'energy',
    contentVersion: contentVersion,
    locale: locale,
    title: locale == 'fa' ? 'یک همراهی سبک' : 'A lighter kind of support',
    message: locale == 'fa'
        ? 'انرژی به‌اشتراک‌گذاشته‌شده امروز پایین است. می‌توانی بدون حدس زدن علت، بخشی از کارهای روزمره را سبک‌تر کنی.'
        : 'Shared energy is lower today. Without guessing why, you can make a small everyday task lighter.',
    cooldown: const Duration(hours: 48),
    supportActionType: 'chores',
    supportActionLabel: locale == 'fa' ? 'کمک در کارها' : 'Help with chores',
  );

  CompanionCareGuidance _gentleCheckIn(String locale) => CompanionCareGuidance(
    id: 'mood.gentle_check_in',
    category: 'mood',
    contentVersion: contentVersion,
    locale: locale,
    title: locale == 'fa' ? 'یک احوال‌پرسی آرام' : 'A gentle check-in',
    message: locale == 'fa'
        ? 'حال به‌اشتراک‌گذاشته‌شده امروز سخت‌تر از معمول است. یک پیام کوتاه و بدون فشار می‌تواند فضای حمایت ایجاد کند.'
        : 'The shared mood is harder today. A short, no-pressure check-in can create room for support.',
    cooldown: const Duration(hours: 48),
    supportActionType: 'check_in',
    supportActionLabel: locale == 'fa' ? 'احوال‌پرسی کردم' : 'I checked in',
  );

  CompanionCareGuidance _phaseAware(String locale) => CompanionCareGuidance(
    id: 'phase.be_present',
    category: 'phase',
    contentVersion: contentVersion,
    locale: locale,
    title: locale == 'fa' ? 'حضور بدون پیش‌فرض' : 'Be present without assumptions',
    message: locale == 'fa'
        ? 'خلاصه فاز چرخه با رضایت به اشتراک گذاشته شده است. بهتر است به‌جای نتیجه‌گیری درباره حال او، فقط آماده شنیدن و همراهی باشی.'
        : 'A cycle-phase summary was shared with consent. Rather than assuming how your partner feels, stay available to listen and support.',
    cooldown: const Duration(hours: 72),
    supportActionType: 'check_in',
    supportActionLabel: locale == 'fa' ? 'احوال‌پرسی کردم' : 'I checked in',
  );

  CompanionCareGuidance _general(String locale) => CompanionCareGuidance(
    id: 'general.ask_first',
    category: 'general',
    contentVersion: contentVersion,
    locale: locale,
    title: locale == 'fa' ? 'اول بپرس، بعد کمک کن' : 'Ask first, then help',
    message: locale == 'fa'
        ? 'اگر می‌خواهی همراهی کنی، یک سؤال ساده مثل «امروز چه کمکی از من می‌خواهی؟» انتخاب را دست خود او نگه می‌دارد.'
        : 'If you want to help, a simple “What would be useful from me today?” keeps the choice with your partner.',
    cooldown: const Duration(hours: 72),
    supportActionType: 'check_in',
    supportActionLabel: locale == 'fa' ? 'پرسیدم' : 'I asked',
  );
}
