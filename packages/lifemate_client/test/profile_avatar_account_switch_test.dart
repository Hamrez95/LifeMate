import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  setUp(LifeMateProfileRefresh.clearCacheForTesting);
  tearDown(LifeMateProfileRefresh.clearCacheForTesting);

  test('clearing the api-client cache prevents avatar leakage across accounts', () async {
    var activeAccount = 'hamid-1';
    var requests = 0;
    final client = LifeMateApiClient(
      baseUri: Uri.parse('https://lifemate.test'),
      accessToken: () => 'test-token',
      httpClient: MockClient((request) async {
        requests += 1;
        final body = activeAccount == 'hamid-1'
            ? {
                'displayName': 'حمید ۱',
                'avatarKey': 'person_green',
                'profilePhotoUrl': 'https://storage.test/hamid-1.jpg',
              }
            : {
                'displayName': 'حمید ۲',
                'avatarKey': 'person_blue',
                'profilePhotoUrl': null,
              };
        return http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(client.close);

    final hamid1 = await LifeMateProfileRefresh.loadProfile(client);
    expect(hamid1['profilePhotoUrl'], 'https://storage.test/hamid-1.jpg');
    expect(requests, 1);

    activeAccount = 'hamid-2';
    final stillCached = await LifeMateProfileRefresh.loadProfile(client);
    expect(stillCached['displayName'], 'حمید ۱');
    expect(requests, 1);

    LifeMateProfileRefresh.clearForApiClient(client);
    final hamid2 = await LifeMateProfileRefresh.loadProfile(client);
    expect(hamid2['displayName'], 'حمید ۲');
    expect(hamid2['profilePhotoUrl'], isNull);
    expect(hamid2['avatarKey'], 'person_blue');
    expect(requests, 2);
  });
}
