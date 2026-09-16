import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_core/lifemate_core.dart';

void main() {
  const requestId = '123e4567-e89b-42d3-a456-426614174100';
  final observedAt = DateTime.utc(2026, 9, 14, 7, 30);
  final localDate = DateTime(2026, 9, 14);
  final createdAt = DateTime.utc(2026, 9, 14, 7, 31);

  test(
    'weight queues canonical Cocoon measurement over health observation domain',
    () {
      final mutation = LifeMateOfflinePregnancyMeasurementMutation.buildCreate(
        mutationId: requestId,
        observationType: ' weight ',
        valuePrimary: 72.4,
        observedAtUtc: observedAt,
        observedLocalDate: localDate,
        timeZone: 'Asia/Tehran',
        note: ' owner note ',
        createdAtUtc: createdAt,
      );

      expect(mutation.domain, LifeMateMutationDomain.healthObservation);
      expect(mutation.method, 'POST');
      expect(mutation.endpointPath, '/api/v1/cocoon/pregnancy/measurements');
      expect(mutation.mutationId, requestId);
      expect(mutation.sourceKey, 'pending-pregnancy-measurement:$requestId');
      expect(mutation.payload, <String, dynamic>{
        'clientRequestId': requestId,
        'observationType': 'weight',
        'valuePrimary': 72.4,
        'valueSecondary': null,
        'note': 'owner note',
        'observedAtUtc': '2026-09-14T07:30:00.000Z',
        'observedLocalDate': '2026-09-14',
        'timeZone': 'Asia/Tehran',
      });
    },
  );

  test('blood pressure preserves canonical systolic and diastolic values', () {
    final mutation = LifeMateOfflinePregnancyMeasurementMutation.buildCreate(
      mutationId: requestId,
      observationType: 'blood_pressure',
      valuePrimary: 118,
      valueSecondary: 76,
      observedAtUtc: observedAt,
      observedLocalDate: localDate,
      timeZone: 'Asia/Tehran',
      createdAtUtc: createdAt,
    );

    expect(mutation.payload['valuePrimary'], 118);
    expect(mutation.payload['valueSecondary'], 76);
  });

  test(
    'unsupported types and invalid canonical values fail before enqueue',
    () {
      expect(
        () => LifeMateOfflinePregnancyMeasurementMutation.buildCreate(
          mutationId: requestId,
          observationType: 'heart_rate',
          valuePrimary: 80,
          observedAtUtc: observedAt,
          observedLocalDate: localDate,
          timeZone: 'Asia/Tehran',
        ),
        throwsArgumentError,
      );
      expect(
        () => LifeMateOfflinePregnancyMeasurementMutation.buildCreate(
          mutationId: requestId,
          observationType: 'blood_pressure',
          valuePrimary: 70,
          valueSecondary: 80,
          observedAtUtc: observedAt,
          observedLocalDate: localDate,
          timeZone: 'Asia/Tehran',
        ),
        throwsArgumentError,
      );
      expect(
        () => LifeMateOfflinePregnancyMeasurementMutation.buildCreate(
          mutationId: requestId,
          observationType: 'weight',
          valuePrimary: 0,
          observedAtUtc: observedAt,
          observedLocalDate: localDate,
          timeZone: 'Asia/Tehran',
        ),
        throwsArgumentError,
      );
    },
  );

  test('request id and note limits preserve replay/idempotency contract', () {
    expect(
      () => LifeMateOfflinePregnancyMeasurementMutation.buildCreate(
        mutationId: 'not-a-uuid',
        observationType: 'blood_glucose',
        valuePrimary: 95,
        observedAtUtc: observedAt,
        observedLocalDate: localDate,
        timeZone: 'Asia/Tehran',
      ),
      throwsArgumentError,
    );
    expect(
      () => LifeMateOfflinePregnancyMeasurementMutation.buildCreate(
        mutationId: requestId,
        observationType: 'blood_glucose',
        valuePrimary: 95,
        observedAtUtc: observedAt,
        observedLocalDate: localDate,
        timeZone: 'Asia/Tehran',
        note: 'x' * 501,
      ),
      throwsArgumentError,
    );
  });
}
