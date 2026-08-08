import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('treatments hub wires dose completion and date range filters', () {
    final source = File(
      'lib/screens/treatments/treatments_screen.dart',
    ).readAsStringSync();

    expect(source, contains('CareItem.fromDoseOccurrence'));
    expect(source, contains("CareItemStatusFilter.completed"));
    expect(source, contains("ValueKey('care-hub-date-range-filter')"));
    expect(source, contains('_loadBoundedRange'));
  });
}
