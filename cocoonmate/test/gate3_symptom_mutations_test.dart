import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  const requestId = '123e4567-e89b-42d3-a456-426614174556';
  final catalog = CocoonApprovedSymptomCatalog(
    version: 'pregnancy-symptoms-v1',
    codes: const ['reviewed-code'],
  );

  test(
    'symptom network fallback queues the same request and catalog intent',
    () async {
      String? onlineId;
      String? queuedId;
      String? queuedCode;
      String? queuedVersion;
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
            }) async {
              onlineId = clientRequestId;
              expect(approvedCatalog.version, 'pregnancy-symptoms-v1');
              throw const LifeMateApiException(
                statusCode: 0,
                code: 'network_timeout',
                message: 'timeout',
              );
            },
        enqueueSymptomOffline:
            ({
              required clientRequestId,
              required observedAtUtc,
              required localDate,
              required symptomCode,
              required intensity,
              required approvedCatalog,
              note,
            }) async {
              queuedId = clientRequestId;
              queuedCode = symptomCode;
              queuedVersion = approvedCatalog.version;
              expect(intensity, 'moderate');
            },
      );

      final result = await adapter.submitSymptom(
        approvedCatalog: catalog,
        symptomCode: 'reviewed-code',
        intensity: CocoonPregnancySymptomIntensity.moderate,
      );

      expect(result.disposition, CocoonGate3MutationDisposition.queued);
      expect(onlineId, requestId);
      expect(queuedId, requestId);
      expect(queuedCode, 'reviewed-code');
      expect(queuedVersion, 'pregnancy-symptoms-v1');
    },
  );

  test('unapproved symptom never reaches network or offline queue', () async {
    var online = false;
    var queued = false;
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
          }) async {
            online = true;
          },
      enqueueSymptomOffline:
          ({
            required clientRequestId,
            required observedAtUtc,
            required localDate,
            required symptomCode,
            required intensity,
            required approvedCatalog,
            note,
          }) async {
            queued = true;
          },
    );

    await expectLater(
      adapter.submitSymptom(
        approvedCatalog: catalog,
        symptomCode: 'unreviewed-code',
        intensity: CocoonPregnancySymptomIntensity.mild,
      ),
      throwsArgumentError,
    );
    expect(online, isFalse);
    expect(queued, isFalse);
  });

  test('authorization failure is never queued as a symptom', () async {
    var queued = false;
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
          }) async {
            throw const LifeMateApiException(
              statusCode: 403,
              code: 'pregnancy_scope_denied',
              message: 'denied',
            );
          },
      enqueueSymptomOffline:
          ({
            required clientRequestId,
            required observedAtUtc,
            required localDate,
            required symptomCode,
            required intensity,
            required approvedCatalog,
            note,
          }) async {
            queued = true;
          },
    );

    await expectLater(
      adapter.submitSymptom(
        approvedCatalog: catalog,
        symptomCode: 'reviewed-code',
        intensity: CocoonPregnancySymptomIntensity.mild,
      ),
      throwsA(isA<LifeMateApiException>()),
    );
    expect(queued, isFalse);
  });
}

CocoonGate3MutationAdapter _adapter({
  required CocoonGate3SymptomOnlineSubmit submitSymptomOnline,
  required CocoonGate3SymptomOfflineEnqueue enqueueSymptomOffline,
}) => CocoonGate3MutationAdapter(
  timeZone: 'Asia/Tehran',
  requestIdFactory: () => '123e4567-e89b-42d3-a456-426614174556',
  clock: () => DateTime(2026, 9, 16, 12),
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
  submitSymptomOnline: submitSymptomOnline,
  enqueueSymptomOffline: enqueueSymptomOffline,
);
