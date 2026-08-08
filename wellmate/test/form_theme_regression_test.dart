import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shared app form themes distinguish hint label and value hierarchy', () {
    for (final path in ['lib/main.dart', '../caremate/lib/main.dart']) {
      final source = File(path).readAsStringSync();
      expect(source, contains('hintStyle: const TextStyle('), reason: path);
      expect(source, contains('Color(0xFF8B95A3)'), reason: path);
      expect(source, contains('labelStyle: const TextStyle('), reason: path);
      expect(source, contains('Color(0xFF667085)'), reason: path);
      expect(source, contains('floatingLabelStyle:'), reason: path);
    }
  });
}
