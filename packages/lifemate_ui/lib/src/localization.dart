import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'locales/en.dart';
import 'locales/fa.dart';
import 'medication_schedule_locales.dart';

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
