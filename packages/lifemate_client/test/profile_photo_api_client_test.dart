import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test('profile photo upload sends authenticated raw bytes and media type', () async {
    late http.Request observed;
    final api = LifeMateApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'access-token',
      httpClient: MockClient((request) async {
        observed = request;
        return http.Response(
          jsonEncode({
            'id': 'profile-1',
            'avatarKey': 'person_blue',
            'profilePhotoUrl': 'https://storage.example.test/signed',
            'version': 2,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final bytes = Uint8List.fromList([0xff, 0xd8, 0xff, 0x00]);

    final result = await api.uploadCurrentProfilePhoto(
      bytes: bytes,
      contentType: 'image/jpeg',
    );

    expect(observed.method, 'PUT');
    expect(observed.url.path, '/api/v1/me/profile/photo');
    expect(observed.headers['authorization'], 'Bearer access-token');
    expect(observed.headers['content-type'], 'image/jpeg');
    expect(observed.bodyBytes, bytes);
    expect(result['profilePhotoUrl'], isNotNull);
  });
}
