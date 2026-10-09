import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test(
    'successful online bootstrap stays usable when local offline setup fails',
    () async {
      var initializationAttempts = 0;
      final api = DurableLifeMateApiClient(
        baseUri: Uri.parse('https://api.example.test'),
        accessToken: () => 'test-token',
        accountId: () => 'authenticated-account',
        innerHttpClient: MockClient((request) async {
          if (request.url.path.endsWith('/api/v1/users/bootstrap')) {
            return http.Response('{}', 200);
          }
          if (request.url.path.endsWith('/api/v1/capabilities')) {
            return http.Response(
              jsonEncode(<String, Object>{
                'accountId': 'canonical-account',
                'selfPersonId': 'person-id',
                'applications': <String>[],
                'features': <String>[],
              }),
              200,
            );
          }
          return http.Response('{}', 404);
        }),
        offlineRuntimeInitializer:
            ({
              required environmentId,
              required accountId,
              required personId,
              required legacyAuthenticatedAccountId,
              required timeZone,
            }) async {
              initializationAttempts++;
              if (initializationAttempts == 1) {
                throw StateError('local store unavailable');
              }
            },
      );
      addTearDown(api.close);

      await api.bootstrapUser(displayName: 'Test', email: 'test@example.test');

      expect(initializationAttempts, 1);
      expect(api.offlineRuntimeAvailable.value, isFalse);

      await api.retryOfflineRuntimeInitialization();

      expect(initializationAttempts, 2);
      expect(api.offlineRuntimeAvailable.value, isTrue);
    },
  );
}
