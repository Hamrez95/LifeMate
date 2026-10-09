import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  const requestId = '123e4567-e89b-42d3-a456-426614174555';
  final localNow = DateTime(2026, 9, 16, 0, 15);

  test('mood transport failure queues the exact canonical intent', () async {
    String? onlineId;
    String? queuedId;
    String? queuedMood;
    final adapter = _adapter(
      clock: () => localNow,
      submitMoodOnline:
          ({
            required clientRequestId,
            required observedAtUtc,
            required localDate,
            required timeZone,
            required mood,
          }) async {
            onlineId = clientRequestId;
            expect(localDate, '2026-09-16');
            expect(timeZone, 'Asia/Tehran');
            expect(mood, CocoonPregnancyMood.veryGood);
            throw const LifeMateApiException(
              statusCode: 0,
              code: 'network_timeout',
              message: 'timeout',
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
            queuedMood = moodCode;
            expect(localDate, DateTime(2026, 9, 16));
          },
    );

    final result = await adapter.submitMood(mood: CocoonPregnancyMood.veryGood);

    expect(result.clientRequestId, requestId);
    expect(result.disposition, CocoonGate3MutationDisposition.queued);
    expect(onlineId, requestId);
    expect(queuedId, requestId);
    expect(queuedMood, 'very_good');
  });

  test(
    'mood authorization failure is never queued as offline success',
    () async {
      var queued = false;
      final adapter = _adapter(
        submitMoodOnline:
            ({
              required clientRequestId,
              required observedAtUtc,
              required localDate,
              required timeZone,
              required mood,
            }) async {
              throw const LifeMateApiException(
                statusCode: 403,
                code: 'pregnancy_scope_denied',
                message: 'denied',
              );
            },
        enqueueMoodOffline:
            ({
              required clientRequestId,
              required observedAtUtc,
              required localDate,
              required moodCode,
            }) async {
              queued = true;
            },
      );

      await expectLater(
        adapter.submitMood(mood: CocoonPregnancyMood.neutral),
        throwsA(
          isA<LifeMateApiException>().having(
            (error) => error.statusCode,
            'statusCode',
            403,
          ),
        ),
      );
      expect(queued, isFalse);
    },
  );
}

CocoonGate3MutationAdapter _adapter({
  CocoonGate3Clock? clock,
  required CocoonGate3MoodOnlineSubmit submitMoodOnline,
  required CocoonGate3MoodOfflineEnqueue enqueueMoodOffline,
}) => CocoonGate3MutationAdapter(
  timeZone: 'Asia/Tehran',
  requestIdFactory: () => '123e4567-e89b-42d3-a456-426614174555',
  clock: clock ?? () => DateTime(2026, 9, 16, 12),
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
);
