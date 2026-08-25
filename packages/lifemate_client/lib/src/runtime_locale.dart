import 'presentation_numbers.dart';

/// Minimal provider-agnostic runtime locale state shared by the two LifeMate
/// Flutter applications and common UI packages.
///
/// App-level LocaleProviders remain the source of truth and update this value
/// whenever the user changes language. Shared widgets that cannot access an
/// app-specific localization delegate can therefore still select safe copy.
class LifeMateRuntimeLocale {
  LifeMateRuntimeLocale._();

  static String _languageCode = 'fa';

  static String get languageCode => _languageCode;
  static bool get isPersian => _languageCode == 'fa';
  static bool get isEnglish => _languageCode == 'en';

  static void setLanguageCode(String languageCode) {
    _languageCode = languageCode.toLowerCase() == 'en' ? 'en' : 'fa';
  }

  static String select({
    required String fa,
    required String en,
    bool? isPersian,
  }) => (isPersian ?? LifeMateRuntimeLocale.isPersian) ? fa : en;

  /// Presentation-only digit normalization. English UI must never inherit
  /// Persian/Arabic digits from stored values or user input.
  static String digits(Object? value) {
    final text = value?.toString() ?? '';
    return isPersian
        ? LifeMateNumbers.toPersian(text)
        : LifeMateNumbers.toLatin(text);
  }

  /// Canonicalizes numeric input before parsing/sending it to APIs.
  static String latinDigits(Object? value) =>
      LifeMateNumbers.toLatin(value?.toString() ?? '');
}
