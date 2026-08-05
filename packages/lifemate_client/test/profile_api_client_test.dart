import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test(
    'profile update sends the selected avatar key to the owner endpoint',
    () async {
      late http.Request observed;
      final api = LifeMateApiClient(
        baseUri: Uri.parse('https://api.example.test'),
        accessToken: () => 'access-token',
        httpClient: MockClient((request) async {
          observed = request;
          return http.Response(
            jsonEncode({
              'id': 'profile-1',
              'userId': 'user-1',
              'displayName': 'Owner',
              'phoneNumber': null,
              'email': 'owner@example.test',
              'locale': 'fa',
              'timeZone': 'Asia/Tehran',
              'avatarKey': 'person_purple',
              'version': 2,
              'createdAtUtc': '2026-08-04T00:00:00Z',
              'updatedAtUtc': '2026-08-04T00:01:00Z',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final result = await api.updateCurrentProfile(
        version: 1,
        displayName: ' Owner ',
        phoneNumber: '',
        locale: 'fa',
        timeZone: 'Asia/Tehran',
        avatarKey: 'person_purple',
      );

      expect(observed.method, 'PATCH');
      expect(observed.url.path, '/api/v1/me/profile');
      expect(observed.headers['authorization'], 'Bearer access-token');
      expect(jsonDecode(observed.body), {
        'version': 1,
        'displayName': 'Owner',
        'phoneNumber': null,
        'locale': 'fa',
        'timeZone': 'Asia/Tehran',
        'avatarKey': 'person_purple',
      });
      expect(result['avatarKey'], 'person_purple');
    },
  );
}
