import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test('round trips a versioned care invitation token', () {
    const token = '0123456789abcdefghijklmnopqrstuvwxyz';

    final payload = CarePairingQr.encodeToken(token);

    expect(payload, startsWith('lifemate://care-invite?'));
    expect(CarePairingQr.tryParseToken(payload), token);
  });

  test('rejects foreign malformed and short payloads', () {
    expect(CarePairingQr.tryParseToken(null), isNull);
    expect(CarePairingQr.tryParseToken(''), isNull);
    expect(CarePairingQr.tryParseToken('https://example.com'), isNull);
    expect(
      CarePairingQr.tryParseToken('lifemate://care-invite?v=2&token=123456789012345678901234'),
      isNull,
    );
    expect(
      CarePairingQr.tryParseToken('lifemate://care-invite?v=1&token=short'),
      isNull,
    );
  });
}
