import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

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
      expect(LifeMateIranPhone.normalizeE164(value), expected, reason: value);
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
      expect(
        () => LifeMateIranPhone.normalizeE164(value),
        throwsA(isA<FormatException>()),
        reason: value,
      );
    }
  });
}
