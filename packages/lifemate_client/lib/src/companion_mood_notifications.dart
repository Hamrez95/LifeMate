class LifeMateCompanionMoodNotificationHistoryItem {
  const LifeMateCompanionMoodNotificationHistoryItem({
    required this.guidanceId,
    required this.shownAtUtc,
  });

  final String guidanceId;
  final DateTime shownAtUtc;
}

class LifeMateCompanionMoodNotification {
  const LifeMateCompanionMoodNotification({
    required this.guidanceId,
    required this.contentVersion,
    required this.title,
    required this.fullBody,
    required this.privateBody,
    required this.trigger,
  });

  final String guidanceId;
  final String contentVersion;
  final String title;
  final String fullBody;
  final String privateBody;
  final String trigger;
}

class LifeMateCompanionMoodNotificationEngine {
  const LifeMateCompanionMoodNotificationEngine();

  static const contentVersion = 'companion-mood-notifications-v1';
  static const _globalCooldown = Duration(hours: 18);
  static const _freshnessWindow = Duration(hours: 8);

  LifeMateCompanionMoodNotification? select({
    required bool receiveMoodSupportNotifications,
    required bool viewSharedWellbeing,
    required bool caregiverNotificationsEnabled,
    required String? loggedOn,
    required String? mood,
    required int? energyLevel,
    required DateTime? updatedAtUtc,
    required List<LifeMateCompanionMoodNotificationHistoryItem> history,
    required String locale,
    required DateTime nowUtc,
  }) {
    if (!receiveMoodSupportNotifications ||
        !viewSharedWellbeing ||
        !caregiverNotificationsEnabled) {
      return null;
    }

    final date = _date(loggedOn);
    final updated = updatedAtUtc?.toUtc();
    final now = nowUtc.toUtc();
    if (date == null || updated == null) return null;
    final age = now.difference(updated);
    if (age < Duration.zero || age > _freshnessWindow) return null;

    if (history.any((item) {
      final elapsed = now.difference(item.shownAtUtc.toUtc());
      return item.guidanceId.startsWith('notify.mood.') &&
          elapsed >= Duration.zero &&
          elapsed < _globalCooldown;
    })) {
      return null;
    }

    final language = locale.toLowerCase().startsWith('fa') ? 'fa' : 'en';
    final normalizedMood = mood?.trim().toLowerCase();

    // One daily shared check-in should never fan out into multiple alerts. Mood
    // gets priority over energy when both are present; the stable per-day key
    // prevents retries or non-material edits from creating a second message.
    if (normalizedMood == 'low' || normalizedMood == 'overwhelmed') {
      return _deduplicated(_mood(language, date), history);
    }
    if (energyLevel != null && energyLevel <= 2) {
      return _deduplicated(_energy(language, date), history);
    }
    return null;
  }

  LifeMateCompanionMoodNotification? _deduplicated(
    LifeMateCompanionMoodNotification candidate,
    List<LifeMateCompanionMoodNotificationHistoryItem> history,
  ) => history.any((item) => item.guidanceId == candidate.guidanceId)
      ? null
      : candidate;

  LifeMateCompanionMoodNotification _mood(String language, String date) =>
      LifeMateCompanionMoodNotification(
        guidanceId: 'notify.mood.check_in.$date',
        contentVersion: contentVersion,
        trigger: 'mood',
        title: language == 'fa' ? 'یک احوال‌پرسی آرام' : 'A gentle check-in',
        fullBody: language == 'fa'
            ? 'حالِ به‌اشتراک‌گذاشته‌شده امروز سخت‌تر ثبت شده است. بدون حدس‌زدن علت، یک پیام کوتاه و بدون فشار می‌تواند همراهی خوبی باشد.'
            : 'Today’s shared mood was recorded as harder. Without guessing why, a short no-pressure check-in can be a kind way to show support.',
        privateBody: language == 'fa'
            ? 'یک به‌روزرسانی خصوصی در CareMate داری. برای جزئیات، اپ را باز کن.'
            : 'You have a private CareMate update. Open the app for details.',
      );

  LifeMateCompanionMoodNotification _energy(String language, String date) =>
      LifeMateCompanionMoodNotification(
        guidanceId: 'notify.mood.energy.$date',
        contentVersion: contentVersion,
        trigger: 'energy',
        title: language == 'fa' ? 'یک همراهی سبک' : 'A lighter kind of support',
        fullBody: language == 'fa'
            ? 'انرژیِ به‌اشتراک‌گذاشته‌شده امروز پایین‌تر ثبت شده است. می‌توانی بدون پیش‌فرض بپرسی آیا کمک کوچکی در کارهای روزمره مفید است یا نه.'
            : 'Today’s shared energy was recorded as lower. Without making assumptions, you can ask whether a small bit of everyday help would be useful.',
        privateBody: language == 'fa'
            ? 'یک به‌روزرسانی خصوصی در CareMate داری. برای جزئیات، اپ را باز کن.'
            : 'You have a private CareMate update. Open the app for details.',
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
