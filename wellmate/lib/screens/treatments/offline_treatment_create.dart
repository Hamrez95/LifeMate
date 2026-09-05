import 'package:lifemate_client/lifemate_client.dart';

/// The locally safe subset for treatment creation is deliberately narrower
/// than generic API retryability. Authorization, validation, conflict and
/// unknown failures must remain visible to the user instead of being converted
/// into an offline success state.
bool isTransientTreatmentCreateFailure(LifeMateApiException error) =>
    error.code == 'network_unavailable' ||
    error.code == 'network_timeout' ||
    error.code == 'retry_budget_exhausted';

/// Queues an already-validated, non-recurring treatment plan only after the
/// medication itself has been confirmed by the server. The same request ID is
/// expected to have been used for the online plan POST so replay stays
/// idempotent if the server committed before the response was lost.
Future<bool> queueTreatmentCreateAfterTransientFailure({
  required LifeMateApiClient api,
  required LifeMateApiException error,
  required String clientRequestId,
  required String medicationId,
  required String doseText,
  String? instructions,
  required DateTime startDate,
  DateTime? endDate,
  required String timeZone,
  required List<Map<String, String>> schedules,
  required int patientReminderMinutesBefore,
  required int caregiverReminderMinutesBefore,
  required bool recurrenceEnabled,
}) async {
  if (recurrenceEnabled || !isTransientTreatmentCreateFailure(error)) {
    return false;
  }
  if (api is! DurableLifeMateApiClient) return false;

  await api.enqueueOfflineTreatmentPlanCreate(
    clientRequestId: clientRequestId,
    medicationId: medicationId,
    doseText: doseText,
    instructions: instructions,
    startDate: startDate,
    endDate: endDate,
    timeZone: timeZone,
    schedules: schedules,
    patientReminderMinutesBefore: patientReminderMinutesBefore,
    caregiverReminderMinutesBefore: caregiverReminderMinutesBefore,
  );
  return true;
}
