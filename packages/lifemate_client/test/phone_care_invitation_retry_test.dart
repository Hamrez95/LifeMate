import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test('phone invitation does not blindly retry failed SMS dependency', () async {
    var requestCount = 0;
    final idempotencyKeys = <String?>[];
    final api = LifeMateApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'access-token',
      httpClient: MockClient((request) async {
        requestCount += 1;
        idempotencyKeys.add(request.headers['idempotency-key']);
        return http.Response(
          jsonEncode({
            'code': 'phone_invitation_delivery_unavailable',
            'detail': 'Phone invitation delivery is temporarily unavailable.',
          }),
          424,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await expectLater(
      api.createPhoneCareInvitation(phone: '+989351234567'),
      throwsA(
        isA<LifeMateApiException>()
            .having((error) => error.statusCode, 'statusCode', 424)
            .having(
              (error) => error.code,
              'code',
              'phone_invitation_delivery_unavailable',
            ),
      ),
    );

    expect(requestCount, 1);
    expect(idempotencyKeys.single, isNotNull);
    expect(idempotencyKeys.single, isNotEmpty);
  });
}
