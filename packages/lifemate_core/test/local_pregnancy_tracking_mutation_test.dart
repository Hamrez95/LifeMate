import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_core/lifemate_core.dart';

void main() {
  test('pregnancy check-in mutation is bounded and replayable', () {
    final mutation = LifeMateOfflinePregnancyTrackingMutation.buildCheckIn(
      mutationId: '11111111-1111-4111-8111-111111111111',
      loggedLocalDate: DateTime(2026, 9, 10),
      timeZone: 'Asia/Tehran',
      feeling: 'mixed',
      energy: 'steady',
      createdAtUtc: DateTime.utc(2026, 9, 9, 22),
    );

    expect(mutation.domain, LifeMateMutationDomain.healthObservation);
    expect(mutation.method, 'POST');
    expect(mutation.endpointPath, '/api/v1/cocoon/pregnancy/check-ins');
    expect(mutation.payload['clientRequestId'], mutation.mutationId);
    expect(mutation.payload['loggedLocalDate'], '2026-09-10');
    expect(mutation.payload['feeling'], 'mixed');
    expect(mutation.payload['energy'], 'steady');
  });

  test('pregnancy symptom mutation preserves exact user capture only', () {
    final observedAt = DateTime.utc(2026, 9, 9, 22, 15);
    final mutation = LifeMateOfflinePregnancyTrackingMutation.buildSymptom(
      mutationId: '22222222-2222-4222-8222-222222222222',
      symptomCode: 'heavy_bleeding',
      intensity: 'strong',
      observedAtUtc: observedAt,
      observedLocalDate: DateTime(2026, 9, 10),
      timeZone: 'Asia/Tehran',
      note: '  user note  ',
      createdAtUtc: DateTime.utc(2026, 9, 9, 22, 16),
    );

    expect(mutation.endpointPath, '/api/v1/cocoon/pregnancy/symptoms');
    expect(mutation.payload['symptomCode'], 'heavy_bleeding');
    expect(mutation.payload['intensity'], 'strong');
    expect(mutation.payload['note'], 'user note');
    expect(mutation.payload['observedAtUtc'], observedAt.toIso8601String());
    expect(mutation.payload.containsKey('safetyHandoff'), isFalse);
    expect(mutation.payload.containsKey('diagnosis'), isFalse);
  });

  test('pregnancy tracking refuses malformed local payloads', () {
    expect(
      () => LifeMateOfflinePregnancyTrackingMutation.buildCheckIn(
        mutationId: 'not-a-uuid',
        loggedLocalDate: DateTime(2026, 9, 10),
        timeZone: 'Asia/Tehran',
        feeling: 'mixed',
        energy: 'steady',
      ),
      throwsArgumentError,
    );

    expect(
      () => LifeMateOfflinePregnancyTrackingMutation.buildSymptom(
        mutationId: '33333333-3333-4333-8333-333333333333',
        symptomCode: '../unsafe',
        intensity: 'strong',
        observedAtUtc: DateTime.utc(2026, 9, 9, 22),
        observedLocalDate: DateTime(2026, 9, 10),
        timeZone: 'Asia/Tehran',
      ),
      throwsArgumentError,
    );
  });
}
