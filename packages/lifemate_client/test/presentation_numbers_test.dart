import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test('Persian digit formatting is presentation-only and reversible', () {
    expect(
      LifeMateNumbers.toPersian('1405/05/17 18:30 3/5'),
      '۱۴۰۵/۰۵/۱۷ ۱۸:۳۰ ۳/۵',
    );
    expect(LifeMateNumbers.toLatin('۱۲۳٤٥'), '12345');
  });

  test('Persian and English numeric input parse safely', () {
    expect(LifeMateNumbers.tryParseInt('۱۲۳'), 123);
    expect(LifeMateNumbers.tryParseInt('123'), 123);
    expect(LifeMateNumbers.tryParseDouble('۳٫۵'), 3.5);
  });
}
