import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_core/lifemate_core.dart';

void main() {
  const checkInId = '123e4567-e89b-42d3-a456-426614174000';
  const symptomId = '123e4567-e89b-42d3-a456-426614174001';
  const moodId = '123e4567-e89b-42d3-a456-426614174002';
  final observedAt = DateTime.utc(2026, 9, 14, 8, 30);
  final localDate = DateTime(2026, 9, 14);
  final createdAt = DateTime.utc(2026, 9, 14, 8, 31);

  test('check-in builds canonical idempotent Cocoon replay mutation', () {
    final mutation = LifeMateOfflinePregnancyDailyMutation.buildCheckIn(
      mutationId: checkInId,
      observedAtUtc: observedAt,
      localDate: localDate,
      timeZone: 'Asia/Tehran',
      feeling: ' comfortable ',
      energy: 'STEADY',
      createdAtUtc: createdAt,
    );

    expect(mutation.domain, LifeMateMutationDomain.healthObservation);
    expect(mutation.method, 'POST');
    expect(mutation.endpointPath, '/api/v1/cocoon/pregnancy/check-ins');
    expect(mutation.mutationId, checkInId);
    expect(mutation.sourceKey, 'pregnancy-check-in:2026-09-14');
    expect(mutation.timeZone, 'Asia/Tehran');
    expect(mutation.payload, <String, dynamic>{
      'clientRequestId': checkInId,
      'observedAtUtc': '2026-09-14T08:30:00.000Z',
      'localDate': '2026-09-14',
      'timeZone': 'Asia/Tehran',
      'feeling': 'comfortable',
      'energy': 'steady',
    });
  });

  test('symptom keeps structured code and bounded private note', () {
    final mutation = LifeMateOfflinePregnancyDailyMutation.buildSymptom(
      mutationId: symptomId,
      observedAtUtc: observedAt,
      localDate: localDate,
      timeZone: 'Asia/Tehran',
      catalogVersion: 'pregnancy-symptoms-v1',
      symptomCode: ' Approved-Nausea ',
      intensity: ' moderate ',
      note: ' private note ',
      createdAtUtc: createdAt,
    );

    expect(mutation.endpointPath, '/api/v1/cocoon/pregnancy/symptoms');
    expect(mutation.sourceKey, 'pregnancy-symptom:$symptomId');
    expect(mutation.payload['catalogVersion'], 'pregnancy-symptoms-v1');
    expect(mutation.payload['symptomCode'], 'approved-nausea');
    expect(mutation.payload['intensity'], 'moderate');
    expect(mutation.payload['note'], 'private note');
  });

  test('mood uses canonical non-diagnostic wire value', () {
    final mutation = LifeMateOfflinePregnancyDailyMutation.buildMood(
      mutationId: moodId,
      observedAtUtc: observedAt,
      localDate: localDate,
      timeZone: 'Asia/Tehran',
      moodCode: 'VERY_GOOD',
      createdAtUtc: createdAt,
    );

    expect(mutation.endpointPath, '/api/v1/cocoon/pregnancy/moods');
    expect(mutation.payload['moodCode'], 'very_good');
  });

  test('invalid request id and unapproved wire values fail before enqueue', () {
    expect(
      () => LifeMateOfflinePregnancyDailyMutation.buildCheckIn(
        mutationId: 'not-a-uuid',
        observedAtUtc: observedAt,
        localDate: localDate,
        timeZone: 'Asia/Tehran',
        feeling: 'comfortable',
        energy: 'steady',
      ),
      throwsArgumentError,
    );
    expect(
      () => LifeMateOfflinePregnancyDailyMutation.buildSymptom(
        mutationId: symptomId,
        observedAtUtc: observedAt,
        localDate: localDate,
        timeZone: 'Asia/Tehran',
        catalogVersion: 'pregnancy-symptoms-v1',
        symptomCode: 'unsafe code with spaces',
        intensity: 'strong',
      ),
      throwsArgumentError,
    );
    expect(
      () => LifeMateOfflinePregnancyDailyMutation.buildMood(
        mutationId: moodId,
        observedAtUtc: observedAt,
        localDate: localDate,
        timeZone: 'Asia/Tehran',
        moodCode: 'diagnosed_depressed',
      ),
      throwsArgumentError,
    );
  });

  test('symptom note remains bounded to the server contract', () {
    expect(
      () => LifeMateOfflinePregnancyDailyMutation.buildSymptom(
        mutationId: symptomId,
        observedAtUtc: observedAt,
        localDate: localDate,
        timeZone: 'Asia/Tehran',
        catalogVersion: 'pregnancy-symptoms-v1',
        symptomCode: 'approved-nausea',
        intensity: 'mild',
        note: 'x' * 401,
      ),
      throwsArgumentError,
    );
  });
}
