enum LifeMateCompanionFertilityState {
  unavailable,
  outsideEstimatedWindow,
  insideEstimatedWindow,
}

class LifeMateCompanionFertilityHistoryItem {
  const LifeMateCompanionFertilityHistoryItem({
    required this.guidanceId,
    required this.shownAtUtc,
  });

  final String guidanceId;
  final DateTime shownAtUtc;
}

class LifeMateCompanionFertilityInsight {
  const LifeMateCompanionFertilityInsight({
    required this.state,
    required this.title,
    required this.body,
    required this.disclaimer,
  });

  final LifeMateCompanionFertilityState state;
  final String title;
  final String body;
  final String disclaimer;
}

class LifeMateCompanionFertilityNotification {
  const LifeMateCompanionFertilityNotification({
    required this.guidanceId,
    required this.contentVersion,
    required this.title,
    required this.fullBody,
    required this.privateBody,
  });

  final String guidanceId;
  final String contentVersion;
  final String title;
  final String fullBody;
  final String privateBody;
}

/// Calendar-estimate communication only.
///
/// This engine never interprets fertility as confirmed ovulation, pregnancy
/// probability, contraception guidance, infertility evidence, or medical advice.
/// It intentionally accepts only already-computed calendar-estimate fields.
class LifeMateCompanionFertilityEngine {
  const LifeMateCompanionFertilityEngine();

  static const notificationContentVersion =
      'companion-fertility-notifications-v1';

  LifeMateCompanionFertilityInsight? insight({
    required bool viewFertilityEstimate,
    required int? cycleDay,
    required int? fertileWindowStartDay,
    required int? fertileWindowEndDay,
    required bool fertilityEstimateReliable,
    required String? confidence,
    required String? cyclePattern,
    required String locale,
  }) {
    if (!viewFertilityEstimate) return null;
    final language = _language(locale);
    if (!_eligibleEstimate(
      cycleDay: cycleDay,
      fertileWindowStartDay: fertileWindowStartDay,
      fertileWindowEndDay: fertileWindowEndDay,
      fertilityEstimateReliable: fertilityEstimateReliable,
      confidence: confidence,
      cyclePattern: cyclePattern,
    )) {
      return LifeMateCompanionFertilityInsight(
        state: LifeMateCompanionFertilityState.unavailable,
        title: language == 'fa'
            ? 'برآورد باروری نامشخص است'
            : 'Fertility estimate is unavailable',
        body: language == 'fa'
            ? 'برای این چرخه، داده کافی و منظم برای نمایش یک بازه احتمالی قابل اتکا وجود ندارد.'
            : 'There is not enough regular cycle history to show a useful estimated fertility window for this cycle.',
        disclaimer: _disclaimer(language),
      );
    }

    final inside = cycleDay! >= fertileWindowStartDay! &&
        cycleDay <= fertileWindowEndDay!;
    return LifeMateCompanionFertilityInsight(
      state: inside
          ? LifeMateCompanionFertilityState.insideEstimatedWindow
          : LifeMateCompanionFertilityState.outsideEstimatedWindow,
      title: language == 'fa'
          ? 'بازه احتمالی باروری'
          : 'Estimated fertility window',
      body: inside
          ? language == 'fa'
              ? 'بر اساس اطلاعات چرخه، این روزها در بازه احتمالی باروری برآورد شده‌اند. اگر برای بارداری برنامه دارید، این فقط می‌تواند شروعی برای گفت‌وگوی دونفره باشد.'
              : 'Based on the recorded cycle information, these days fall within the estimated fertility window. If you are planning a pregnancy, this can simply be a prompt for a conversation together.'
          : language == 'fa'
              ? 'برآورد تقویمی فعلی، این روز را خارج از بازه احتمالی باروری نشان می‌دهد.'
              : 'The current calendar estimate places this day outside the estimated fertility window.',
      disclaimer: _disclaimer(language),
    );
  }

  LifeMateCompanionFertilityNotification? notification({
    required bool viewFertilityEstimate,
    required bool receiveFertilityNotifications,
    required bool caregiverNotificationsEnabled,
    required String? cycleStart,
    required int? cycleDay,
    required int? fertileWindowStartDay,
    required int? fertileWindowEndDay,
    required bool fertilityEstimateReliable,
    required String? confidence,
    required String? cyclePattern,
    required List<LifeMateCompanionFertilityHistoryItem> history,
    required String locale,
  }) {
    if (!viewFertilityEstimate ||
        !receiveFertilityNotifications ||
        !caregiverNotificationsEnabled ||
        !_eligibleEstimate(
          cycleDay: cycleDay,
          fertileWindowStartDay: fertileWindowStartDay,
          fertileWindowEndDay: fertileWindowEndDay,
          fertilityEstimateReliable: fertilityEstimateReliable,
          confidence: confidence,
          cyclePattern: cyclePattern,
        )) {
      return null;
    }
    if (cycleDay! < fertileWindowStartDay! || cycleDay > fertileWindowEndDay!) {
      return null;
    }
    final start = _date(cycleStart);
    if (start == null) return null;
    final guidanceId = 'notify.fertility.window.$start';
    if (history.any((item) => item.guidanceId == guidanceId)) return null;

    final language = _language(locale);
    return LifeMateCompanionFertilityNotification(
      guidanceId: guidanceId,
      contentVersion: notificationContentVersion,
      title: language == 'fa'
          ? 'بازه احتمالی باروری'
          : 'Estimated fertility window',
      fullBody: language == 'fa'
          ? 'بر اساس اطلاعات چرخه، این روزها در بازه احتمالی باروری برآورد شده‌اند. این برآورد، تأیید تخمک‌گذاری یا توصیه پزشکی نیست؛ اگر برای بارداری برنامه دارید، شاید زمان خوبی برای گفت‌وگو با هم باشد.'
          : 'Based on the recorded cycle information, these days are within the estimated fertility window. This does not confirm ovulation and is not medical advice; if you are planning a pregnancy, it may be a useful time to talk together.',
      privateBody: language == 'fa'
          ? 'یک به‌روزرسانی خصوصی در CareMate داری. برای جزئیات، اپ را باز کن.'
          : 'You have a private CareMate update. Open the app for details.',
    );
  }

  static bool _eligibleEstimate({
    required int? cycleDay,
    required int? fertileWindowStartDay,
    required int? fertileWindowEndDay,
    required bool fertilityEstimateReliable,
    required String? confidence,
    required String? cyclePattern,
  }) {
    if (!fertilityEstimateReliable ||
        confidence?.toLowerCase() == 'low' ||
        cyclePattern?.toLowerCase() != 'regular' ||
        cycleDay == null ||
        fertileWindowStartDay == null ||
        fertileWindowEndDay == null ||
        cycleDay < 1 ||
        fertileWindowStartDay < 1 ||
        fertileWindowEndDay < fertileWindowStartDay) {
      return false;
    }
    return true;
  }

  static String _disclaimer(String language) => language == 'fa'
      ? 'این فقط یک برآورد تقویمی بر اساس اطلاعات چرخه است؛ برای پیشگیری از بارداری، تشخیص ناباروری یا تأیید تخمک‌گذاری استفاده نشود.'
      : 'This is only a calendar estimate based on recorded cycle information. Do not use it for contraception, infertility diagnosis, or confirmation of ovulation.';

  static String _language(String locale) =>
      locale.toLowerCase().startsWith('fa') ? 'fa' : 'en';

  static String? _date(String? value) {
    final text = value?.trim() ?? '';
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) return null;
    final parsed = DateTime.tryParse('${text}T00:00:00Z');
    return parsed == null || parsed.toIso8601String().substring(0, 10) != text
        ? null
        : text;
  }
}
