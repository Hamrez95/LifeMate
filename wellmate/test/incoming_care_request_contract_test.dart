import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'incoming caregiver request only shows accept and reject for real rows',
    () {
      final source = File(
        'lib/screens/profile/care_access_screen.dart',
      ).readAsStringSync();
      expect(source, contains('getIncomingCareRequests()'));
      expect(source, contains('IncomingCareRequestCard'));
      expect(source, contains('_respondToCareRequest(request, accept: true)'));
      expect(source, contains('_respondToCareRequest(request, accept: false)'));
    },
  );
}
