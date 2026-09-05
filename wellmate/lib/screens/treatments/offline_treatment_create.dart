import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

typedef WellMateOfflineTreatmentCreateEnqueuer = Future<void> Function(
  WellMateOfflineTreatmentCreateRequest request,
);

class WellMateOfflineTreatmentCreateRequest {
  const WellMateOfflineTreatmentCreateRequest({
    required this.clientRequestId,
    required this.medicationId,
    required this.doseText,
    required this.instructions,
    required this.startDate,
    required this.endDate,
    required this.timeZone,
    required this.schedules,
    required this.patientReminderMinutesBefore,
    required this.caregiverReminderMinutesBefore,
  });

  final String clientRequestId;
  final String medicationId;
  final String doseText;
  final String? instructions;
  final DateTime startDate;
  final DateTime? endDate;
  final String timeZone;
  final List<Map<String, String>> schedules;
  final int patientReminderMinutesBefore;
  final int caregiverReminderMinutesBefore;
}

bool canQueueTreatmentCreateOffline(LifeMateApiException error) =>
    !kIsWeb &&
    const <String>{
      'network_unavailable',
      'network_timeout',
      'retry_budget_exhausted',
    }.contains(error.code);

Future<bool> tryQueueTreatmentCreateOffline(
  BuildContext context,
  WellMateOfflineTreatmentCreateRequest request, {
  WellMateOfflineTreatmentCreateEnqueuer? injectedEnqueuer,
}) async {
  if (kIsWeb) return false;
  try {
    if (injectedEnqueuer != null) {
      await injectedEnqueuer(request);
      return true;
    }
    final apiClient = context.read<LifeMateApiClient>();
    if (apiClient is! DurableLifeMateApiClient) return false;
    await apiClient.enqueueOfflineTreatmentPlanCreate(
      clientRequestId: request.clientRequestId,
      medicationId: request.medicationId,
      doseText: request.doseText,
      instructions: request.instructions,
      startDate: request.startDate,
      endDate: request.endDate,
      timeZone: request.timeZone,
      schedules: request.schedules,
      patientReminderMinutesBefore: request.patientReminderMinutesBefore,
      caregiverReminderMinutesBefore: request.caregiverReminderMinutesBefore,
    );
    return true;
  } catch (error) {
    if (kDebugMode) {
      debugPrint(
        'Offline treatment create enqueue unavailable: ${error.runtimeType}',
      );
    }
    return false;
  }
}
