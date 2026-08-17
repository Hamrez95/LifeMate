import 'package:flutter_test/flutter_test.dart';
import 'package:wellmate/core/utils/iranian_mobile_input.dart';

void main() {
  test('normalizes supported Iranian mobile input variants', () {
    const expected = '+989351234567';
    for (final value in <String>[
      '09351234567',
      '+989351234567',
      '989351234567',
      '00989351234567',
      '9351234567',
      '۰۹۳۵ ۱۲۳ ۴۵۶۷',
      '٠٩٣٥-١٢٣-٤٥٦٧',
      ' (0935) 123 4567 ',
    ]) {
      expect(normalizeIranianMobileInput(value), expected, reason: value);
    }
  });

  test('rejects non-Iran and malformed mobile input', () {
    for (final value in <String>[
      '',
      '02112345678',
      '+994501234567',
      '0912123456',
      '091212345678',
      'hello',
    ]) {
      expect(normalizeIranianMobileInput(value), isNull, reason: value);
    }
  });
}
