import 'package:flutter/material.dart';

/// Canonical locale metadata for LifeMate presentation surfaces.
///
/// Feature/domain identifiers remain language-neutral. Locale behavior such as
/// direction, fallback, numerals and display name belongs here instead of in
/// individual screens.
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

/// A language-neutral key/value catalog with deterministic fallback.
///
/// The catalog is intentionally small and framework-agnostic so feature packs
/// can be generated from ARB/JSON later without changing feature widgets. A
/// screen asks for a semantic key; adding a locale changes catalog data, not
/// widget branching logic.
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

  static String _interpolate(
    String template,
    Map<String, Object?> params,
  ) {
    var result = template;
    for (final entry in params.entries) {
      result = result.replaceAll('{${entry.key}}', '${entry.value ?? ''}');
    }
    return result;
  }
}

/// Canonical shared catalog. Feature-specific catalogs can be generated and
/// merged later while preserving this API.
const LifeMateMessageCatalog lifeMateMessages = LifeMateMessageCatalog(
  <String, Map<String, String>>{
    'en': <String, String>{
      'common.cancel': 'Cancel',
      'common.save': 'Save',
      'common.retry': 'Try again',
      'common.close': 'Close',
      'common.loading': 'Loading…',
      'common.notEnoughInformation': 'Not enough information',
      'women.dailyLog.title': 'Daily period log',
      'women.dailyLog.logToday': 'Log today',
      'women.analytics.title': 'My stats & patterns',
      'women.analytics.full': 'View full analytics',
      'women.circle.create': 'Create Circle',
      'women.circle.noSharing': 'No sharing',
      'women.insights.settings': 'Cycle Insight settings',
    },
    'fa': <String, String>{
      'common.cancel': 'انصراف',
      'common.save': 'ذخیره',
      'common.retry': 'تلاش دوباره',
      'common.close': 'بستن',
      'common.loading': 'در حال بارگذاری…',
      'common.notEnoughInformation': 'اطلاعات کافی نیست',
      'women.dailyLog.title': 'ثبت روزانه پریود',
      'women.dailyLog.logToday': 'ثبت حال امروز',
      'women.analytics.title': 'آمار و الگوهای من',
      'women.analytics.full': 'مشاهده آمار کامل',
      'women.circle.create': 'ساخت Circle',
      'women.circle.noSharing': 'بدون اشتراک',
      'women.insights.settings': 'تنظیمات بینش چرخه',
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

/// Isolates content with a known direction inside the ambient app direction.
/// Useful for phone numbers, email, OTP, URLs and identifiers in RTL locales.
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
