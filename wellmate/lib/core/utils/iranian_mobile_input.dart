/// UX-side normalization for Iranian mobile input.
///
/// The server remains authoritative and validates the contact again before any
/// invitation is persisted or delivered. This helper only keeps the WellMate
/// form consistent with the accepted server input shapes and supports Persian
/// and Arabic-Indic digits entered from mobile keyboards.
String? normalizeIranianMobileInput(String value) {
  var normalized = _toAsciiDigits(value.trim()).replaceAll(
    RegExp(r'[\s()\-]'),
    '',
  );

  if (normalized.startsWith('0098')) {
    normalized = '+98${normalized.substring(4)}';
  } else if (normalized.startsWith('98')) {
    normalized = '+$normalized';
  } else if (normalized.startsWith('09')) {
    normalized = '+98${normalized.substring(1)}';
  } else if (RegExp(r'^9\d{9}$').hasMatch(normalized)) {
    normalized = '+98$normalized';
  }

  return RegExp(r'^\+989\d{9}$').hasMatch(normalized) ? normalized : null;
}

String _toAsciiDigits(String value) {
  final buffer = StringBuffer();
  for (final rune in value.runes) {
    if (rune >= 0x06F0 && rune <= 0x06F9) {
      buffer.writeCharCode(0x30 + rune - 0x06F0);
    } else if (rune >= 0x0660 && rune <= 0x0669) {
      buffer.writeCharCode(0x30 + rune - 0x0660);
    } else {
      buffer.writeCharCode(rune);
    }
  }
  return buffer.toString();
}
