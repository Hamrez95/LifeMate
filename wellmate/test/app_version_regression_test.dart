import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wellmate/core/constants/app_version.dart';

void main() {
  test('displayed app version matches wellmate pubspec', () {
    final versionLine = File(
      'pubspec.yaml',
    ).readAsLinesSync().firstWhere((line) => line.startsWith('version:'));
    final pubspecVersion = versionLine.substring('version:'.length).trim();

    expect(wellMateAppVersion, pubspecVersion);
  });
}
