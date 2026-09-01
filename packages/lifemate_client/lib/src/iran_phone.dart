final class LifeMateIranPhone {
  const LifeMateIranPhone._();

  /// Normalizes an Iranian mobile number to canonical E.164 (`+989xxxxxxxxx`).
  ///
  /// This is an authentication/contact identifier only. It must never be used
  /// as a Person identifier or healthcare authorization boundary.
  static String normalizeE164(String value) {
    var normalized = _asciiDigits(value.trim())
        .replaceAll(RegExp(r'[\s()\-]'), '');

    if (normalized.startsWith('0098')) {
      normalized = '+98${normalized.substring(4)}';
    } else if (normalized.startsWith('98')) {
      normalized = '+$normalized';
    } else if (normalized.startsWith('09')) {
      normalized = '+98${normalized.substring(1)}';
    } else if (RegExp(r'^9\d{9}$').hasMatch(normalized)) {
      normalized = '+98$normalized';
    }

    if (!RegExp(r'^\+989\d{9}$').hasMatch(normalized)) {
      throw const FormatException('Invalid Iranian mobile number.');
    }
    return normalized;
  }

  static String _asciiDigits(String value) {
    final buffer = StringBuffer();
    for (final rune in value.runes) {
      if (rune >= 0x06F0 && rune <= 0x06F9) {
        buffer.write(rune - 0x06F0);
        continue;
      }
      if (rune >= 0x0660 && rune <= 0x0669) {
        buffer.write(rune - 0x0660);
        continue;
      }
      buffer.writeCharCode(rune);
    }
    return buffer.toString();
  }
}

/// Compatibility validator for UI flows that need a nullable result instead of
/// throwing while the user is still typing.
String? normalizeIranianMobileE164(String value) {
  try {
    return LifeMateIranPhone.normalizeE164(value);
  } on FormatException {
    return null;
  }
}
