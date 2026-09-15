import 'package:cocoonmate/app/cocoon_gate3_mutations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  const requestId = '123e4567-e89b-42d3-a456-426614174000';
  final localNow = DateTime(2026, 9, 16, 0, 15);

  test('check-in online success is server-confirmed and never queued', () async {
    String? onlineId;
    String? onlineDate;
    var queued = false;
    final adapter = _adapter(
      clock: () => localNow,
      submitCheckInOnline: ({
        required clientRequestId,
        required observedAtUtc,
        required localDate,
        required timeZone,
        required feeling,
        required energy,
      }) async {
        onlineId = clientRequestId;
        onlineDate = localDate;
        expect(timeZone, 'Asia/Tehran');
        expect(feeling, CocoonPregnancyFeeling.comfortable);
        expect(energy, CocoonPregnancyEnergy.steady);
      },
      enqueueCheckInOffline: ({
        required clientRequestId,
        required observedAtUtc,
        required localDate,
        required feeling,
        required energy,
      }) async {
        queued = true;
      },
    );

    final result = await adapter.submitCheckIn(
      feeling: CocoonPregnancyFeeling.comfortable,
      energy: CocoonPregnancyEnergy.steady,
    );

    expect(result.clientRequestId, requestId);
    expect(result.disposition, CocoonGate3MutationDisposition.confirmed);
    expect(onlineId, requestId);
    expect(onlineDate, '2026-09-16');
    expect(queued, isFalse);
  });

  test('network failure queues check-in with the exact same request id', () async {
    String? onlineId;
    String? queuedId;
    String? queuedFeeling;
    String? queuedEnergy;
    final adapter = _adapter(
      clock: () => localNow,
      submitCheckInOnline: ({
        required clientRequestId,
        required observedAtUtc,
        required localDate,
        required timeZone,
        required feeling,
        required energy,
      }) async {
        onlineId = clientRequestId;
        throw const LifeMateApiException(
          statusCode: 0,
          code: 'network_unavailable',
          message: 'offline',
        );
      },
      enqueueCheckInOffline: ({
        required clientRequestId,
        required observedAtUtc,
        required localDate,
        required feeling,
        required energy,
      }) async {
        queuedId = clientRequestId;
        queuedFeeling = feeling;
        queuedEnergy = energy;
        expect(localDate, DateTime(2026, 9, 16));
      },
    );

    final result = await adapter.submitCheckIn(
      feeling: CocoonPregnancyFeeling.difficult,
      energy: CocoonPregnancyEnergy.low,
    );

    expect(result.disposition, CocoonGate3MutationDisposition.queued);
    expect(onlineId, requestId);
    expect(queuedId, requestId);
    expect(queuedFeeling, 'difficult');
    expect(queuedEnergy, 'low');
  });

  test('authorization failure is never converted into an offline queue', () async {
    var queued = false;
    final adapter = _adapter(
      submitCheckInOnline: ({
        required clientRequestId,
        required observedAtUtc,
        required localDate,
        required timeZone,
        required feeling,
        required energy,
      }) async {
        throw const LifeMateApiException(
          statusCode: 403,
          code: 'pregnancy_scope_denied',
          message: 'denied',
        );
      },
      enqueueCheckInOffline: ({
        required clientRequestId,
        required observedAtUtc,
        required localDate,
        required feeling,
        required energy,
      }) async {
        queued = true;
      },
    );

    await expectLater(
      adapter.submitCheckIn(
        feeling: CocoonPregnancyFeeling.mixed,
        energy: CocoonPregnancyEnergy.high,
      ),
      throwsA(
        isA<LifeMateApiException>().having(
          (error) => error.statusCode,
          'statusCode',
          403,
        ),
      ),
    );
    expect(queued, isFalse);
  });

  test('measurement retry preserves canonical type, values and request id', () async {
    String? onlineId;
    String? queuedId;
    String? queuedType;
    double? queuedPrimary;
    double? queuedSecondary;
    final adapter = _adapter(
      clock: () => localNow,
      submitMeasurementOnline: ({
        required clientRequestId,
        required type,
        required valuePrimary,
        valueSecondary,
        note,
        required observedAtUtc,
        required observedLocalDate,
        required timeZone,
      }) async {
        onlineId = clientRequestId;
        expect(type, CocoonPregnancyMeasurementType.bloodPressure);
        expect(valuePrimary, 118);
        expect(valueSecondary, 76);
        throw const LifeMateApiException(
          statusCode: 0,
          code: 'network_timeout',
          message: 'timeout',
        );
      },
      enqueueMeasurementOffline: ({
        required clientRequestId,
        required observationType,
        required valuePrimary,
        valueSecondary,
        note,
        required observedAtUtc,
        required observedLocalDate,
      }) async {
        queuedId = clientRequestId;
        queuedType = observationType;
        queuedPrimary = valuePrimary;
        queuedSecondary = valueSecondary;
        expect(observedLocalDate, DateTime(2026, 9, 16));
      },
    );

    final result = await adapter.submitMeasurement(
      type: CocoonPregnancyMeasurementType.bloodPressure,
      valuePrimary: 118,
      valueSecondary: 76,
    );

    expect(result.disposition, CocoonGate3MutationDisposition.queued);
    expect(onlineId, requestId);
    expect(queuedId, requestId);
    expect(queuedType, 'blood_pressure');
    expect(queuedPrimary, 118);
    expect(queuedSecondary, 76);
  });
}

CocoonGate3MutationAdapter _adapter({
  CocoonGate3Clock? clock,
  CocoonGate3CheckInOnlineSubmit? submitCheckInOnline,
  CocoonGate3CheckInOfflineEnqueue? enqueueCheckInOffline,
  CocoonGate3MeasurementOnlineSubmit? submitMeasurementOnline,
  CocoonGate3MeasurementOfflineEnqueue? enqueueMeasurementOffline,
}) {
  return CocoonGate3MutationAdapter(
    timeZone: 'Asia/Tehran',
    requestIdFactory: () => '123e4567-e89b-42d3-a456-426614174000',
    clock: clock ?? () => DateTime(2026, 9, 16, 12),
    submitCheckInOnline:
        submitCheckInOnline ??
        ({
          required clientRequestId,
          required observedAtUtc,
          required localDate,
          required timeZone,
          required feeling,
          required energy,
        }) async {},
    enqueueCheckInOffline:
        enqueueCheckInOffline ??
        ({
          required clientRequestId,
          required observedAtUtc,
          required localDate,
          required feeling,
          required energy,
        }) async {},
    submitMeasurementOnline:
        submitMeasurementOnline ??
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
        enqueueMeasurementOffline ??
        ({
          required clientRequestId,
          required observationType,
          required valuePrimary,
          valueSecondary,
          note,
          required observedAtUtc,
          required observedLocalDate,
        }) async {},
  );
}
