import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  const requestId = '123e4567-e89b-42d3-a456-426614174811';
  final catalog = CocoonApprovedSymptomCatalog(
    version: 'pregnancy-symptoms-v1',
    codes: const <String>['nausea'],
  );

  test('network mood fallback queues the exact request id once', () async {
    String? onlineId;
    String? queuedId;
    final adapter = _adapter(
      submitMoodOnline:
          ({
            required clientRequestId,
            required observedAtUtc,
            required localDate,
            required timeZone,
            required mood,
          }) async {
            onlineId = clientRequestId;
            throw const LifeMateApiException(
              statusCode: 0,
              code: 'network_unavailable',
              message: 'offline',
            );
          },
      enqueueMoodOffline:
          ({
            required clientRequestId,
            required observedAtUtc,
            required localDate,
            required moodCode,
          }) async {
            queuedId = clientRequestId;
            expect(moodCode, 'good');
          },
    );

    final result = await adapter.submitMood(mood: CocoonPregnancyMood.good);

    expect(result.disposition, CocoonGate3MutationDisposition.queued);
    expect(result.clientRequestId, requestId);
    expect(onlineId, requestId);
    expect(queuedId, requestId);
  });

  test('authorization failures never queue a mood capture', () async {
    var queued = false;
    final adapter = _adapter(
      submitMoodOnline:
          ({
            required clientRequestId,
            required observedAtUtc,
            required localDate,
            required timeZone,
            required mood,
          }) async => throw const LifeMateApiException(
            statusCode: 403,
            code: 'pregnancy_owner_required',
            message: 'denied',
          ),
      enqueueMoodOffline:
          ({
            required clientRequestId,
            required observedAtUtc,
            required localDate,
            required moodCode,
          }) async => queued = true,
    );

    await expectLater(
      adapter.submitMood(mood: CocoonPregnancyMood.neutral),
      throwsA(isA<LifeMateApiException>()),
    );
    expect(queued, isFalse);
  });

  test(
    'unapproved symptoms are rejected before network or durable queue',
    () async {
      var onlineCalls = 0;
      var queuedCalls = 0;
      final adapter = _adapter(
        submitSymptomOnline:
            ({
              required clientRequestId,
              required observedAtUtc,
              required localDate,
              required timeZone,
              required approvedCatalog,
              required symptomCode,
              required intensity,
              note,
            }) async => onlineCalls++,
        enqueueSymptomOffline:
            ({
              required clientRequestId,
              required observedAtUtc,
              required localDate,
              required symptomCode,
              required intensity,
              required approvedCatalog,
              note,
            }) async => queuedCalls++,
      );

      await expectLater(
        adapter.submitSymptom(
          approvedCatalog: catalog,
          symptomCode: 'invented-symptom',
          intensity: CocoonPregnancySymptomIntensity.mild,
        ),
        throwsArgumentError,
      );
      expect(onlineCalls, 0);
      expect(queuedCalls, 0);
    },
  );
}

CocoonGate3MutationAdapter _adapter({
  CocoonGate3MoodOnlineSubmit? submitMoodOnline,
  CocoonGate3MoodOfflineEnqueue? enqueueMoodOffline,
  CocoonGate3SymptomOnlineSubmit? submitSymptomOnline,
  CocoonGate3SymptomOfflineEnqueue? enqueueSymptomOffline,
}) => CocoonGate3MutationAdapter(
  timeZone: 'Asia/Tehran',
  requestIdFactory: () => '123e4567-e89b-42d3-a456-426614174811',
  clock: () => DateTime.utc(2026, 9, 24, 9),
  submitCheckInOnline:
      ({
        required clientRequestId,
        required observedAtUtc,
        required localDate,
        required timeZone,
        required feeling,
        required energy,
      }) async {},
  enqueueCheckInOffline:
      ({
        required clientRequestId,
        required observedAtUtc,
        required localDate,
        required feeling,
        required energy,
      }) async {},
  submitMeasurementOnline:
      ({
        required clientRequestId,
        required type,
        required valuePrimary,
        valueSecondary,
        note,
        required observedAtUtc,
        required observedLocalDate,
        required timeZone,
      }) async {},
  enqueueMeasurementOffline:
      ({
        required clientRequestId,
        required observationType,
        required valuePrimary,
        valueSecondary,
        note,
        required observedAtUtc,
        required observedLocalDate,
      }) async {},
  submitMoodOnline: submitMoodOnline,
  enqueueMoodOffline: enqueueMoodOffline,
  submitSymptomOnline: submitSymptomOnline,
  enqueueSymptomOffline: enqueueSymptomOffline,
);
