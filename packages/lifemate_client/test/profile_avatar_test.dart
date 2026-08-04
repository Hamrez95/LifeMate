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

  testWidgets('avatar picker reports the selected persisted key', (tester) async {
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

    await tester.tap(find.byKey(const ValueKey('profile-avatar-person_purple')));
    await tester.pumpAndSettle();

    expect(selected, 'person_purple');
  });
}
