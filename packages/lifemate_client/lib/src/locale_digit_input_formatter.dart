import 'package:flutter/services.dart';

import 'presentation_numbers.dart';
import 'runtime_locale.dart';

/// Keeps numeric input canonical without changing the Persian experience.
///
/// In English mode Persian/Arabic digits typed by a locale-specific keyboard
/// are immediately converted to ASCII digits. Digit substitution is one UTF-16
/// code unit for one code unit, so selection/composing offsets stay valid.
class LifeMateLocaleDigitInputFormatter extends TextInputFormatter {
  const LifeMateLocaleDigitInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!LifeMateRuntimeLocale.isEnglish) return newValue;
    final normalized = LifeMateNumbers.toLatin(newValue.text);
    if (normalized == newValue.text) return newValue;
    return newValue.copyWith(text: normalized);
  }
}
