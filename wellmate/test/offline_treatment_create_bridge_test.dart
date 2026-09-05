import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:wellmate/screens/treatments/offline_treatment_create.dart';

void main() {
  test('only transient transport failures qualify for offline treatment create', () {
    for (final code in <String>[
      'network_unavailable',
      'network_timeout',
      'retry_budget_exhausted',
    ]) {
      expect(
        canQueueTreatmentCreateOffline(
          LifeMateApiException(statusCode: 503, code: code, message: code),
        ),
        isTrue,
      );
    }

    for (final entry in <(int, String)>[
      (401, 'unauthorized'),
      (403, 'forbidden'),
      (409, 'database_conflict'),
      (422, 'validation_failed'),
    ]) {
      expect(
        canQueueTreatmentCreateOffline(
          LifeMateApiException(
            statusCode: entry.$1,
            code: entry.$2,
            message: entry.$2,
          ),
        ),
        isFalse,
      );
    }
  });

  testWidgets('bridge preserves exact validated treatment payload and request id', (
    tester,
  ) async {
    BuildContext? context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (value) {
            context = value;
            return const SizedBox();
          },
        ),
      ),
    );

    final request = WellMateOfflineTreatmentCreateRequest(
      clientRequestId: 'treatment-create-request-123',
      medicationId: '123e4567-e89b-42d3-a456-426614174700',
      doseText: '1 tablet',
      instructions: 'after food',
      startDate: DateTime(2026, 9, 5),
      endDate: DateTime(2026, 9, 12),
      timeZone: 'Asia/Tehran',
      schedules: const <Map<String, String>>[
        <String, String>{'dayOfWeek': 'saturday', 'localTime': '08:15'},
        <String, String>{'dayOfWeek': 'monday', 'localTime': '20:45'},
      ],
      patientReminderMinutesBefore: 15,
      caregiverReminderMinutesBefore: 30,
    );
    WellMateOfflineTreatmentCreateRequest? captured;

    final queued = await tryQueueTreatmentCreateOffline(
      context!,
      request,
      injectedEnqueuer: (value) async => captured = value,
    );

    expect(queued, isTrue);
    expect(captured, same(request));
    expect(captured!.clientRequestId, 'treatment-create-request-123');
    expect(captured!.medicationId, '123e4567-e89b-42d3-a456-426614174700');
    expect(captured!.doseText, '1 tablet');
    expect(captured!.instructions, 'after food');
    expect(captured!.timeZone, 'Asia/Tehran');
    expect(captured!.schedules, request.schedules);
    expect(captured!.patientReminderMinutesBefore, 15);
    expect(captured!.caregiverReminderMinutesBefore, 30);
  });
}
