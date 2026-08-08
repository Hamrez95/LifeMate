import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  setUp(LifeMateProfileRefresh.clearCacheForTesting);
  tearDown(LifeMateProfileRefresh.clearCacheForTesting);

  test(
    'clears the previous account avatar when authenticated user changes',
    () {
      final client = LifeMateApiClient(
        baseUri: Uri.parse('https://lifemate.test'),
        accessToken: () => 'test-token',
      );
      addTearDown(client.close);

      LifeMateProfileRefresh.cacheProfile(client, {
        'displayName': 'Hamidreza',
        'avatarKey': 'person_blue',
        'profilePhotoUrl': 'https://storage.test/hamidreza.jpg',
      });
      expect(
        LifeMateProfileRefresh.peek(client)?['profilePhotoUrl'],
        'https://storage.test/hamidreza.jpg',
      );

      final revisionBefore = LifeMateProfileRefresh.revision.value;
      LifeMateProfileRefresh.clearForApiClient(client);

      expect(LifeMateProfileRefresh.peek(client), isNull);
      expect(LifeMateProfileRefresh.revision.value, revisionBefore + 1);

      LifeMateProfileRefresh.cacheProfile(client, {
        'displayName': 'Reyhaneh',
        'avatarKey': 'person_green',
        'profilePhotoUrl': 'https://storage.test/reyhaneh.jpg',
      });
      expect(
        LifeMateProfileRefresh.peek(client)?['profilePhotoUrl'],
        'https://storage.test/reyhaneh.jpg',
      );
    },
  );
}
