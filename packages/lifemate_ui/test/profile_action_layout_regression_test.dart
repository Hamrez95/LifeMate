import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('supplemental profile actions are integrated into the profile menu', () {
    final wrapper = File(
      'lib/src/shared_profile_with_privacy.dart',
    ).readAsStringSync();
    final profile = File('lib/src/shared_profile_screen.dart').readAsStringSync();

    expect(wrapper, contains('additionalActions: supplementalActions'));
    expect(wrapper, isNot(contains('OutlinedButton.icon(')));
    expect(
      wrapper,
      isNot(contains('SafeArea(')),
      reason: 'Shared profile destinations must not be rendered in a fixed footer.',
    );

    expect(profile, contains('final List<LifeMateProfileAdditionalAction> additionalActions'));
    expect(profile, contains('for (final action in additionalActions)'));
    expect(profile, contains('child: _ProfileMenuTile('));
  });
}
