import 'package:flutter/widgets.dart';

/// Presentation-only number localization.
///
/// API payloads, IDs, DateTime values, persistence and logs must keep their
/// machine-readable representation. UI code can safely normalize user input
/// back to Latin digits before parsing.
abstract final class LifeMateNumbers {
  static const _latin = '0123456789';
  static const _persian = '۰۱۲۳۴۵۶۷۸۹';
  static const _arabicIndic = '٠١٢٣٤٥٦٧٨٩';

  static String toPersian(Object? value) {
    final input = value?.toString() ?? '';
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      final character = String.fromCharCode(rune);
      var index = _latin.indexOf(character);
      if (index < 0) index = _arabicIndic.indexOf(character);
      buffer.write(index < 0 ? character : _persian[index]);
    }
    return buffer.toString();
  }

  static String toLatin(Object? value) {
    final input = value?.toString() ?? '';
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      final character = String.fromCharCode(rune);
      var index = _persian.indexOf(character);
      if (index < 0) index = _arabicIndic.indexOf(character);
      buffer.write(index < 0 ? character : _latin[index]);
    }
    return buffer.toString();
  }

  static bool usesPersianDigits(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'fa';

  static String localize(BuildContext context, Object? value) =>
      usesPersianDigits(context) ? toPersian(value) : toLatin(value);

  static int? tryParseInt(Object? value) => int.tryParse(toLatin(value).trim());

  static double? tryParseDouble(Object? value) =>
      double.tryParse(toLatin(value).trim().replaceAll('٫', '.'));
}
