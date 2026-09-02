import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('profile secondary actions stay in one compact rail', () {
    final source = File(
      'lib/src/shared_profile_with_privacy.dart',
    ).readAsStringSync();

    expect(source, contains('height: 58'));
    expect(source, contains('mainAxisAlignment: MainAxisAlignment.spaceEvenly'));
    expect(source, contains("ValueKey('profile-feedback')"));
    expect(source, contains("ValueKey('profile-demographics')"));
    expect(source, contains("ValueKey('profile-privacy-preferences')"));
    expect(
      source,
      isNot(contains('minimumSize: const Size.fromHeight(52)')),
      reason: 'Secondary actions must not return to stacked full-width buttons.',
    );
  });
}
