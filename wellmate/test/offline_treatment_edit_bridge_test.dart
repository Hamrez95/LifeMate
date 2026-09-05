import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:wellmate/screens/treatments/offline_treatment_edit.dart';

void main() {
  test('only explicit transient network failures are offline-queue candidates', () {
    for (final code in const <String>{
      'network_unavailable',
      'network_timeout',
      'retry_budget_exhausted',
    }) {
      expect(
        canQueueTreatmentEditOffline(
          LifeMateApiException(statusCode: 0, code: code, message: code),
        ),
        isTrue,
      );
    }

    for (final error in const <LifeMateApiException>[
      LifeMateApiException(
        statusCode: 401,
        code: 'invalid_session',
        message: 'unauthorized',
      ),
      LifeMateApiException(
        statusCode: 403,
        code: 'forbidden',
        message: 'forbidden',
      ),
      LifeMateApiException(
        statusCode: 409,
        code: 'stale_treatment_plan',
        message: 'conflict',
      ),
      LifeMateApiException(
        statusCode: 400,
        code: 'validation_failed',
        message: 'invalid',
      ),
    ]) {
      expect(canQueueTreatmentEditOffline(error), isFalse);
    }
  });

  testWidgets('injected bridge receives one opaque-idempotent treatment edit', (
    tester,
  ) async {
    WellMateOfflineTreatmentEditRequest? captured;
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (value) {
            context = value;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final request = WellMateOfflineTreatmentEditRequest(
      clientRequestId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      treatmentPlanId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      version: 4,
      medicationVersion: 2,
      medicationName: 'test medicine',
      strengthText: '10 mg',
      form: 'tablet',
      doseText: '1 tablet',
      instructions: 'after food',
      startDate: DateTime(2026, 9, 5),
      endDate: null,
      timeZone: 'Asia/Tehran',
      schedules: const <Map<String, String>>[
        <String, String>{'dayOfWeek': 'monday', 'localTime': '08:00'},
      ],
      patientReminderMinutesBefore: 30,
      caregiverReminderMinutesBefore: 60,
      status: 'active',
    );

    final queued = await tryQueueTreatmentEditOffline(
      context,
      request,
      injectedEnqueuer: (value) async => captured = value,
    );

    expect(queued, isTrue);
    expect(captured, same(request));
    expect(captured!.clientRequestId, request.clientRequestId);
    expect(captured!.version, 4);
    expect(captured!.medicationVersion, 2);
    expect(tester.takeException(), isNull);
  });
}
