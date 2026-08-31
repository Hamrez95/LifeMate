import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'locales/en.dart';
import 'locales/fa.dart';
import 'medication_schedule_locales.dart';

const Map<String, String> medicationSchedulePersianMessages = <String, String>{
  'medication.schedule.rules.sectionTitle': 'قواعد زمان‌بندی هر دارو',
  'medication.schedule.rules.sectionDescription': 'در این بخش فقط محدودیت‌هایی را ثبت می‌کنی که خودت می‌دانی. LifeMate تداخل دارویی یا ایمنی پزشکی را بررسی نمی‌کند.',
  'medication.schedule.rules.empty': 'فعلاً داروی فعالی برای تنظیم زمان‌بندی نداری.',
  'medication.schedule.rules.title': 'قواعد زمان‌بندی',
  'medication.schedule.rules.fixed': 'زمان ثابت',
  'medication.schedule.rules.fixedTitle': 'این زمان ثابت بماند',
  'medication.schedule.rules.fixedDescription': 'وقتی روشن است، این دارو وارد هیچ پیشنهاد جابه‌جایی خودکار نمی‌شود.',
  'medication.schedule.rules.nearby': 'پیشنهاد زمان نزدیک مجاز',
  'medication.schedule.rules.nearbyTitle': 'اجازه پیشنهاد برای زمان‌های نزدیک',
  'medication.schedule.rules.nearbyDescription': 'فقط اجازه ساخت پیش‌نمایش می‌دهد؛ هیچ زمان مصرفی بدون تأیید تو تغییر نمی‌کند.',
  'medication.schedule.rules.spacingSaved': 'دستور فاصله ثبت شده',
  'medication.schedule.rules.spacingTitle': 'دستور فاصله زمانی',
  'medication.schedule.rules.spacingDescription': 'فقط فاصله‌ای را وارد کن که در نسخه یا دستور پزشک/داروساز به تو گفته شده است. LifeMate این مقدار را از نظر پزشکی بررسی یا استنباط نمی‌کند.',
  'medication.schedule.rules.minutesBefore': 'دقیقه قبل',
  'medication.schedule.rules.minutesAfter': 'دقیقه بعد',
  'medication.schedule.rules.note': 'توضیح اختیاری دستور',
  'medication.schedule.rules.saved': 'قواعد زمان‌بندی ذخیره شد.',
  'medication.schedule.rules.saveFailed': 'ذخیره قواعد زمان‌بندی انجام نشد.',
  'medication.schedule.rules.stale': 'این تنظیمات جای دیگری تغییر کرده بود. آخرین نسخه بارگذاری شد؛ دوباره بررسی و ذخیره کن.',
  'medication.schedule.rules.invalidSpacing': 'فاصله باید عددی بین ۰ تا ۱۴۴۰ دقیقه باشد.',
  'medication.schedule.rules.noteTooLong': 'توضیح فاصله حداکثر ۲۴۰ نویسه است.',
  'medication.schedule.rules.explicitSchedule': 'برنامه با ساعت‌های مشخص',
  'medication.schedule.rules.daily24': 'روزانه · هر ۲۴ ساعت',
  'medication.schedule.rules.every2Days48': 'هر ۲ روز · ۴۸ ساعت',
  'medication.schedule.rules.everyHours': 'هر {hours} ساعت',
  'medication.schedule.rules.recurring': 'برنامه تکرارشونده',
  'medication.optimization.nearby.title': 'یکپارچه‌سازی زمان‌های نزدیک',
  'medication.optimization.nearby.info': 'این قابلیت فقط زمان‌هایی را که خودت وارد کرده‌ای نزدیک‌تر می‌کند. LifeMate تداخل دارویی، ایمنی یا مناسب‌بودن مصرف همزمان را بررسی نمی‌کند.',
  'medication.optimization.nearby.scheduleChanged': 'برنامه دارو تغییر کرده است. دوباره بررسی کن.',
  'medication.optimization.nearby.previewFailed': 'پیشنهاد زمان‌بندی آماده نشد. دوباره تلاش کن.',
  'medication.optimization.nearby.previewConnection': 'پیشنهاد زمان‌بندی آماده نشد. اتصال را بررسی کن.',
  'medication.optimization.nearby.applyTitle': 'اعمال تغییر زمان‌ها؟',
  'medication.optimization.nearby.applyDescription': 'فقط زمان شروع برنامه‌های نشان‌داده‌شده تغییر می‌کند. فاصله مصرف هر دارو دقیقاً ثابت می‌ماند. LifeMate تداخل دارویی را بررسی نمی‌کند.',
  'medication.optimization.nearby.confirmApply': 'تأیید و اعمال',
  'medication.optimization.nearby.stale': 'این پیشنهاد دیگر معتبر نیست. یک پیش‌نمایش تازه بگیر.',
  'medication.optimization.nearby.applyFailed': 'اعمال تغییرات انجام نشد. دوباره تلاش کن.',
  'medication.optimization.nearby.applyConnection': 'اعمال تغییرات انجام نشد. اتصال را بررسی کن.',
  'medication.optimization.nearby.appliedInfo': 'تغییرات تأییدشده اعمال شد. فاصله زمانی اصلی هر دارو دست‌نخورده مانده است. تا وقتی برنامه را دوباره تغییر نداده‌ای، می‌توانی این تغییر زمان را برگردانی.',
  'medication.optimization.nearby.undoAction': 'بازگردانی زمان‌ها',
  'medication.optimization.nearby.undoSuccess': 'زمان‌های قبلی برگردانده شد. فاصله مصرف داروها همچنان تغییر نکرده است.',
  'medication.optimization.nearby.undoStale': 'بعد از اعمال، برنامه تغییر کرده است و بازگردانی خودکار امن نیست. برنامه را دوباره بررسی کن.',
  'medication.optimization.nearby.undoFailed': 'بازگردانی انجام نشد. دوباره تلاش کن.',
  'medication.optimization.nearby.undoConnection': 'بازگردانی انجام نشد. اتصال را بررسی کن.',
  'medication.optimization.nearby.reason.locked': 'زمان این دارو قفل است',
  'medication.optimization.nearby.reason.spacing': 'برای این دارو دستور فاصله ثبت شده',
  'medication.optimization.nearby.reason.notOptedIn': 'پیشنهاد زمان نزدیک برای این دارو فعال نیست',
  'medication.optimization.nearby.reason.ambiguous': 'گروه زمانی مبهم بود؛ تغییری پیشنهاد نشد',
  'medication.optimization.nearby.reason.noCandidate': 'زمان نزدیک دیگری پیدا نشد',
  'medication.optimization.nearby.noChanges': 'فعلاً دو برنامه واجد شرایط با فاصله کمتر از ۳۰ دقیقه پیدا نشد. هیچ زمانی تغییر نکرد.',
  'medication.optimization.nearby.previewTitle': 'پیش‌نمایش تغییرات',
  'medication.optimization.nearby.notificationReduction': 'در این پیش‌نمایش حدود {count} اعلان جداگانه کمتر می‌شود.',
  'medication.optimization.nearby.applyChanges': 'اعمال تغییرات',
  'medication.optimization.nearby.unchangedItems': 'موارد بدون تغییر',
  'medication.optimization.nearby.proposedTime': 'زمان پیشنهادی',
  'medication.optimization.nearby.exactInterval': 'فاصله هر {hours} ساعت بدون تغییر می‌ماند.',
  'medication.grouped.title': 'داروهای این نوبت',
  'medication.grouped.explanation': 'این اعلان فقط زمان‌های ثبت‌شده را کنار هم نشان می‌دهد و درباره تداخل یا ایمنی داروها تصمیم نمی‌گیرد. وضعیت هر دارو را جداگانه ثبت کنید.',
  'medication.grouped.staleDose': 'این نوبت تغییر کرده است. صفحه برنامه را تازه کنید.',
  'medication.grouped.saveFailed': 'ثبت وضعیت انجام نشد. دوباره تلاش کنید.',
  'medication.grouped.snoozed': 'برای ۱۰ دقیقه بعد یادآوری می‌کنیم.',
  'medication.grouped.statusRecorded': 'وضعیت ثبت شد.',
  'medication.grouped.taken': 'مصرف کردم',
  'medication.grouped.skipped': 'مصرف نشد',
  'medication.grouped.notification.title': 'وقت مصرف {count} دارو',
  'medication.grouped.notification.emptyBody': 'داروهای برنامه‌ریزی‌شده را بررسی کنید.',
  'medication.grouped.notification.more': '{visible} و {count} مورد دیگر',
  'medication.grouped.notification.reviewAction': 'بررسی داروها',
};

@immutable
class LifeMateLocaleSpec {
  const LifeMateLocaleSpec({
    required this.locale,
    required this.textDirection,
    required this.englishName,
    required this.nativeName,
    required this.fallbackLanguageCode,
    this.usesPersianDigitsByDefault = false,
  });

  final Locale locale;
  final TextDirection textDirection;
  final String englishName;
  final String nativeName;
  final String fallbackLanguageCode;
  final bool usesPersianDigitsByDefault;

  String get languageCode => locale.languageCode.toLowerCase();
  bool get isRtl => textDirection == TextDirection.rtl;
}

abstract final class LifeMateLocaleRegistry {
  static const String defaultLanguageCode = 'en';
  static const List<LifeMateLocaleSpec> supported = <LifeMateLocaleSpec>[
    LifeMateLocaleSpec(
      locale: Locale('fa'),
      textDirection: TextDirection.rtl,
      englishName: 'Persian',
      nativeName: 'فارسی',
      fallbackLanguageCode: 'en',
      usesPersianDigitsByDefault: true,
    ),
    LifeMateLocaleSpec(
      locale: Locale('en'),
      textDirection: TextDirection.ltr,
      englishName: 'English',
      nativeName: 'English',
      fallbackLanguageCode: 'en',
    ),
  ];

  static final Map<String, LifeMateLocaleSpec> _byLanguage =
      <String, LifeMateLocaleSpec>{
        for (final spec in supported) spec.languageCode: spec,
      };

  static LifeMateLocaleSpec resolve(Locale? locale) {
    final code = locale?.languageCode.toLowerCase();
    return _byLanguage[code] ?? _byLanguage[defaultLanguageCode]!;
  }

  static Locale resolveLocale(Locale? requested) => resolve(requested).locale;
  static bool isSupported(Locale locale) =>
      _byLanguage.containsKey(locale.languageCode.toLowerCase());
}

@immutable
class LifeMateMessageCatalog {
  const LifeMateMessageCatalog(this._messages);
  final Map<String, Map<String, String>> _messages;

  String text(
    String key, {
    required Locale locale,
    Map<String, Object?> params = const <String, Object?>{},
  }) {
    final spec = LifeMateLocaleRegistry.resolve(locale);
    final localized = _messages[spec.languageCode]?[key];
    final fallback = _messages[spec.fallbackLanguageCode]?[key] ??
        _messages[LifeMateLocaleRegistry.defaultLanguageCode]?[key];
    final template = localized ?? fallback;
    if (template == null) {
      assert(false, 'Missing LifeMate localization key: $key');
      return key;
    }
    return _interpolate(template, params);
  }

  bool hasCompleteKey(String key) => LifeMateLocaleRegistry.supported.every(
        (spec) => _messages[spec.languageCode]?.containsKey(key) == true,
      );

  Set<String> missingKeysFor(Locale locale, Iterable<String> requiredKeys) {
    final language = LifeMateLocaleRegistry.resolve(locale).languageCode;
    final values = _messages[language] ?? const <String, String>{};
    return requiredKeys.where((key) => !values.containsKey(key)).toSet();
  }

  Set<String> allKeysFor(Locale locale) {
    final language = LifeMateLocaleRegistry.resolve(locale).languageCode;
    return (_messages[language] ?? const <String, String>{}).keys.toSet();
  }

  static String _interpolate(String template, Map<String, Object?> params) {
    var result = template;
    for (final entry in params.entries) {
      result = result.replaceAll('{${entry.key}}', '${entry.value ?? ''}');
    }
    return result;
  }
}

const LifeMateMessageCatalog lifeMateMessages = LifeMateMessageCatalog(
  <String, Map<String, String>>{
    'en': <String, String>{
      ...lifeMateEnglishMessages,
      ...medicationScheduleEnglishMessages,
    },
    'fa': <String, String>{
      ...lifeMatePersianMessages,
      ...medicationSchedulePersianMessages,
    },
  },
);

extension LifeMateLocalizationContext on BuildContext {
  LifeMateLocaleSpec get lifeMateLocale =>
      LifeMateLocaleRegistry.resolve(Localizations.maybeLocaleOf(this));
  bool get lifeMateIsRtl => lifeMateLocale.isRtl;
  String tr(
    String key, {
    Map<String, Object?> params = const <String, Object?>{},
  }) =>
      lifeMateMessages.text(
        key,
        locale: lifeMateLocale.locale,
        params: params,
      );
}

/// Accepts Latin, Persian and Arabic-Indic digits while normalizing the model
/// value to ASCII. This keeps numeric health/timing payloads locale-independent
/// without making Persian users switch keyboards.
class LifeMateLocaleDigitInputFormatter extends TextInputFormatter {
  const LifeMateLocaleDigitInputFormatter();

  static const Map<String, String> _digits = <String, String>{
    '۰': '0',
    '۱': '1',
    '۲': '2',
    '۳': '3',
    '۴': '4',
    '۵': '5',
    '۶': '6',
    '۷': '7',
    '۸': '8',
    '۹': '9',
    '٠': '0',
    '١': '1',
    '٢': '2',
    '٣': '3',
    '٤': '4',
    '٥': '5',
    '٦': '6',
    '٧': '7',
    '٨': '8',
    '٩': '9',
  };

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final normalized = newValue.text
        .split('')
        .map((character) => _digits[character] ?? character)
        .join();
    return newValue.copyWith(text: normalized);
  }
}

class LifeMateBidiText extends StatelessWidget {
  const LifeMateBidiText(
    this.text, {
    super.key,
    required this.textDirection,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });

  final String text;
  final TextDirection textDirection;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: textDirection,
        child: Text(
          text,
          style: style,
          textAlign: textAlign,
          maxLines: maxLines,
          overflow: overflow,
        ),
      );
}
