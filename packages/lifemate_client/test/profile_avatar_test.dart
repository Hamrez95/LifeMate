import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test('profile avatar catalog is deterministic and rejects unknown keys', () {
    expect(
      LifeMateProfileAvatars.options.map((option) => option.key).toSet().length,
      LifeMateProfileAvatars.options.length,
    );
    expect(
      LifeMateProfileAvatars.normalize('unknown-avatar'),
      LifeMateProfileAvatars.defaultKey,
    );
    expect(LifeMateProfileAvatars.isAllowed('person_green'), isTrue);
  });

  testWidgets('avatar picker reports the selected persisted key', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LifeMateAvatarPicker(
            selectedKey: LifeMateProfileAvatars.defaultKey,
            onSelected: (value) => selected = value,
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('profile-avatar-person_purple')),
    );
    await tester.pumpAndSettle();

    expect(selected, 'person_purple');
  });
  testWidgets('current-user avatar refreshes after a profile mutation signal', (
    WidgetTester tester,
  ) async {
    final api = _RefreshingProfileApiClient();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LifeMateCurrentUserAvatar(apiClient: api)),
      ),
    );
    await tester.pumpAndSettle();

    var avatar = tester.widget<LifeMateProfileAvatar>(
      find.byType(LifeMateProfileAvatar),
    );
    expect(avatar.avatarKey, 'person_blue');

    LifeMateProfileRefresh.notifyChanged();
    await tester.pumpAndSettle();

    avatar = tester.widget<LifeMateProfileAvatar>(
      find.byType(LifeMateProfileAvatar),
    );
    expect(avatar.avatarKey, 'heart_coral');
    expect(api.requests, 2);
  });
}

class _RefreshingProfileApiClient extends LifeMateApiClient {
  _RefreshingProfileApiClient()
    : super(
        baseUri: Uri.parse('https://example.invalid'),
        accessToken: () => 'test-token',
      );

  int requests = 0;

  @override
  Future<Map<String, dynamic>> getCurrentProfile() async {
    requests += 1;
    return <String, dynamic>{
      'avatarKey': requests == 1 ? 'person_blue' : 'heart_coral',
    };
  }
}
