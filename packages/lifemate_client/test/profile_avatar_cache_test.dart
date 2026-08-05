import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  setUp(LifeMateProfileRefresh.clearCacheForTesting);
  tearDown(LifeMateProfileRefresh.clearCacheForTesting);

  test(
    'deduplicates concurrent profile loads and reuses the signed URL',
    () async {
      var requests = 0;
      final client = LifeMateApiClient(
        baseUri: Uri.parse('https://lifemate.test'),
        accessToken: () => 'test-token',
        httpClient: MockClient((request) async {
          requests += 1;
          expect(request.method, 'GET');
          expect(request.url.path, '/api/v1/me/profile');
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return http.Response(
            jsonEncode({
              'displayName': 'Hamidreza',
              'avatarKey': 'person_blue',
              'profilePhotoUrl': 'https://storage.test/signed-photo',
              'version': requests,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.close);

      final results = await Future.wait([
        LifeMateProfileRefresh.loadProfile(client),
        LifeMateProfileRefresh.loadProfile(client),
        LifeMateProfileRefresh.loadProfile(client),
      ]);

      expect(requests, 1);
      expect(results.map((profile) => profile['profilePhotoUrl']).toSet(), {
        'https://storage.test/signed-photo',
      });

      final cached = await LifeMateProfileRefresh.loadProfile(client);
      expect(cached['version'], 1);
      expect(requests, 1);

      final refreshed = await LifeMateProfileRefresh.loadProfile(
        client,
        force: true,
      );
      expect(refreshed['version'], 2);
      expect(requests, 2);
    },
  );

  test('publishes a write response without another network request', () async {
    var requests = 0;
    final client = LifeMateApiClient(
      baseUri: Uri.parse('https://lifemate.test'),
      accessToken: () => 'test-token',
      httpClient: MockClient((request) async {
        requests += 1;
        return http.Response('{}', 200);
      }),
    );
    addTearDown(client.close);

    LifeMateProfileRefresh.cacheProfile(client, {
      'avatarKey': 'person_green',
      'profilePhotoUrl': 'https://storage.test/new-signed-photo',
      'version': 3,
    });

    final cached = await LifeMateProfileRefresh.loadProfile(client);
    expect(cached['avatarKey'], 'person_green');
    expect(cached['version'], 3);
    expect(requests, 0);
  });
}
