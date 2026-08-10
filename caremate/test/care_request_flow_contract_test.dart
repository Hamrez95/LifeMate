import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('care page exposes caregiver initiated email request flow', () {
    final source = File(
      'lib/screens/feature_preview_screen.dart',
    ).readAsStringSync();
    expect(source, contains('createCareRequest(email: email)'));
    expect(source, contains('getOutgoingCareRequests()'));
  });
}
