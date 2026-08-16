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
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    final buffer = StringBuffer();
    for (final rune in value.runes) {
      final char = String.fromCharCode(rune);
      final persianIndex = persian.indexOf(char);
      if (persianIndex >= 0) {
        buffer.write(persianIndex);
        continue;
      }
      final arabicIndex = arabic.indexOf(char);
      if (arabicIndex >= 0) {
        buffer.write(arabicIndex);
        continue;
      }
      buffer.write(char);
    }
    return buffer.toString();
  }
}
