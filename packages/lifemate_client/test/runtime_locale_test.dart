import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  tearDown(() {
    LifeMateRuntimeLocale.setLanguageCode('fa');
  });

  test('English runtime locale selects English copy and Latin digits', () {
    LifeMateRuntimeLocale.setLanguageCode('en');

    expect(
      LifeMateRuntimeLocale.select(fa: 'سلام', en: 'Hello'),
      'Hello',
    );
    expect(LifeMateRuntimeLocale.digits('۱۲٣45'), '12345');
    expect(LifeMateRuntimeLocale.latinDigits('۱۲٣45'), '12345');
  });

  test('Persian runtime locale preserves Persian presentation', () {
    LifeMateRuntimeLocale.setLanguageCode('fa');

    expect(
      LifeMateRuntimeLocale.select(fa: 'سلام', en: 'Hello'),
      'سلام',
    );
    expect(LifeMateRuntimeLocale.digits('123'), '۱۲۳');
  });

  test('English numeric input formatter canonicalizes typed digits', () {
    LifeMateRuntimeLocale.setLanguageCode('en');
    const formatter = LifeMateLocaleDigitInputFormatter();

    final result = formatter.formatEditUpdate(
      const TextEditingValue(text: ''),
      const TextEditingValue(
        text: '۱۲٣45',
        selection: TextSelection.collapsed(offset: 5),
      ),
    );

    expect(result.text, '12345');
    expect(result.selection.baseOffset, 5);
  });

  test('Persian numeric input formatter leaves typed digits untouched', () {
    LifeMateRuntimeLocale.setLanguageCode('fa');
    const formatter = LifeMateLocaleDigitInputFormatter();

    final result = formatter.formatEditUpdate(
      const TextEditingValue(text: ''),
      const TextEditingValue(text: '۱۲۳'),
    );

    expect(result.text, '۱۲۳');
  });
}
