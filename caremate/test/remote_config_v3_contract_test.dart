import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CareMate startup is wrapped by the shared runtime config gate', () {
    final source = File('lib/main.dart').readAsStringSync();
    expect(source, contains('LifeMateRuntimeConfigGate('));
    expect(source, contains("product: 'caremate'"));
    expect(source, contains('currentVersion: careMateAppVersion'));
  });

  test('CareMate pairing fails closed while existing active care can continue', () {
    final source = File('lib/screens/caremate_root_shell.dart').readAsStringSync();
    expect(source, contains("'client.care_pairing.enabled'"));
    expect(source, contains('_CareMateRemotePairingOffGate'));
    expect(source, contains('_hasActiveRelationship'));
    expect(source, contains('defaultValue: false'));
  });
}
