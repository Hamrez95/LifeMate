import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_core/lifemate_core_web.dart';

void main() {
  test('shared client web seam can reference protected offline contract types', () {
    LifeMateLocalHealthStore? store;
    final record = LifeMateLocalProjectionRecord(
      domain: LifeMateLocalProjectionDomain.careEvent,
      recordKey: 'event-1',
      payload: const <String, dynamic>{},
      storedAtUtc: DateTime.utc(2026, 9, 5),
    );

    expect(store, isNull);
    expect(record.domain, LifeMateLocalProjectionDomain.careEvent);
  });
}
