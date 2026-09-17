import 'package:cocoonmate/app/cocoon_gate3_read_models.dart';
import 'package:cocoonmate_module/cocoonmate_module.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test(
    'canonical record source identity is retained without health payload',
    () {
      final record = CocoonPregnancyRecordItem.fromJson({
        'id': 'measurement:record-1',
        'sourceKind': 'health_observation',
        'sourceId': '11111111-1111-4111-8111-111111111111',
        'category': 'measurements',
        'occurredAtUtc': '2026-09-17T10:30:00.000Z',
        'localDate': '2026-09-17',
        'type': 'weight',
        'summary': {'observationType': 'weight', 'valuePrimary': 70.5},
        'deepLink': '  lifemate://health/observations/record-1  ',
        'sourceVersion': 4,
      });

      final identity = CocoonRecordSourceIdentity.fromCanonical(record);

      expect(identity.sourceKind, 'health_observation');
      expect(identity.sourceId, '11111111-1111-4111-8111-111111111111');
      expect(identity.deepLink, 'lifemate://health/observations/record-1');
      expect(identity.sourceVersion, 4);
    },
  );

  test(
    'Gate-3 read models resolve source identity by presentation id only',
    () {
      const identity = CocoonRecordSourceIdentity(
        sourceKind: 'dose_occurrence',
        sourceId: '22222222-2222-4222-8222-222222222222',
        sourceVersion: 7,
      );
      final models = CocoonGate3ReadModels(
        calendarState: CocoonCalendarLoadState.empty,
        calendarItems: const [],
        calendarAsOfLocalDate: DateTime(2026, 9, 17),
        recordsState: CocoonRecordsState.ready,
        records: const [],
        recordSources: const {'dose:record-2': identity},
      );

      expect(models.sourceForRecord('dose:record-2'), same(identity));
      expect(
        models.sourceForRecord('22222222-2222-4222-8222-222222222222'),
        isNull,
      );
    },
  );

  test('missing canonical deep link remains absent instead of fabricated', () {
    final record = CocoonPregnancyRecordItem.fromJson({
      'id': 'checkin:record-3',
      'sourceKind': 'pregnancy_check_in',
      'sourceId': '33333333-3333-4333-8333-333333333333',
      'category': 'check_ins',
      'occurredAtUtc': '2026-09-17T11:00:00.000Z',
      'localDate': '2026-09-17',
      'type': 'daily_check_in',
      'summary': <String, dynamic>{},
      'deepLink': '   ',
    });

    final identity = CocoonRecordSourceIdentity.fromCanonical(record);

    expect(identity.deepLink, isNull);
    expect(identity.sourceVersion, isNull);
  });
}
