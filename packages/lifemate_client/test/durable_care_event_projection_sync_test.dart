import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test('durable care-event sync fails closed before canonical runtime adoption', () async {
    final api = DurableLifeMateApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'token',
      accountId: () => 'legacy-auth-subject',
    );

    await expectLater(
      api.syncCareEventProjections(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Canonical shared offline runtime'),
        ),
      ),
    );

    api.close();
  });
}
