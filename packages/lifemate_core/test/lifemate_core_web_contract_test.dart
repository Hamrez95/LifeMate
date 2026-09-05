import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_core/lifemate_core_web.dart';

void main() {
  test('web projection contracts exactly mirror native domain wire names', () {
    expect(
      LifeMateLocalProjectionDomain.values
          .map((value) => value.wireName)
          .toSet(),
      equals(<String>{
        'treatment_plan',
        'treatment_occurrence',
        'care_event',
        'women_health_cycle',
        'pregnancy_snapshot',
        'pregnancy_content',
        'health_observation',
        'pending_mutation',
        'notification_schedule',
        'sync_metadata',
      }),
    );
  });

  test('web projection record preserves read-only shared shape', () {
    final storedAt = DateTime.utc(2026, 9, 5, 6);
    final record = LifeMateLocalProjectionRecord(
      domain: LifeMateLocalProjectionDomain.treatmentOccurrence,
      recordKey: 'occurrence-1',
      payload: const <String, dynamic>{'status': 'scheduled'},
      storedAtUtc: storedAt,
      sourceRevision: '7',
    );

    expect(record.domain, LifeMateLocalProjectionDomain.treatmentOccurrence);
    expect(record.recordKey, 'occurrence-1');
    expect(record.payload['status'], 'scheduled');
    expect(record.storedAtUtc, storedAt);
    expect(record.sourceRevision, '7');
  });
}
