import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

typedef WellMateOfflineTreatmentEditEnqueuer = Future<void> Function(
  WellMateOfflineTreatmentEditRequest request,
);

class WellMateOfflineTreatmentEditRequest {
  const WellMateOfflineTreatmentEditRequest({
    required this.clientRequestId,
    required this.treatmentPlanId,
    required this.version,
    required this.medicationVersion,
    required this.medicationName,
    required this.strengthText,
    required this.form,
    required this.doseText,
    required this.instructions,
    required this.startDate,
    required this.endDate,
    required this.timeZone,
    required this.schedules,
    required this.patientReminderMinutesBefore,
    required this.caregiverReminderMinutesBefore,
    required this.status,
  });

  final String clientRequestId;
  final String treatmentPlanId;
  final int version;
  final int medicationVersion;
  final String medicationName;
  final String? strengthText;
  final String? form;
  final String doseText;
  final String? instructions;
  final DateTime startDate;
  final DateTime? endDate;
  final String timeZone;
  final List<Map<String, String>> schedules;
  final int patientReminderMinutesBefore;
  final int caregiverReminderMinutesBefore;
  final String status;
}

bool canQueueTreatmentEditOffline(LifeMateApiException error) =>
    !kIsWeb &&
    const <String>{
      'network_unavailable',
      'network_timeout',
      'retry_budget_exhausted',
    }.contains(error.code);

Future<bool> tryQueueTreatmentEditOffline(
  BuildContext context,
  WellMateOfflineTreatmentEditRequest request, {
  WellMateOfflineTreatmentEditEnqueuer? injectedEnqueuer,
}) async {
  if (kIsWeb) return false;
  try {
    if (injectedEnqueuer != null) {
      await injectedEnqueuer(request);
      return true;
    }
    final apiClient = context.read<LifeMateApiClient>();
    if (apiClient is! DurableLifeMateApiClient) return false;
    await apiClient.enqueueOfflineTreatmentPlanEdit(
      clientRequestId: request.clientRequestId,
      treatmentPlanId: request.treatmentPlanId,
      version: request.version,
      medicationVersion: request.medicationVersion,
      medicationName: request.medicationName,
      strengthText: request.strengthText,
      form: request.form,
      doseText: request.doseText,
      instructions: request.instructions,
      startDate: request.startDate,
      endDate: request.endDate,
      timeZone: request.timeZone,
      schedules: request.schedules,
      patientReminderMinutesBefore: request.patientReminderMinutesBefore,
      caregiverReminderMinutesBefore: request.caregiverReminderMinutesBefore,
      status: request.status,
    );
    return true;
  } catch (error) {
    if (kDebugMode) {
      debugPrint(
        'Offline treatment edit enqueue unavailable: ${error.runtimeType}',
      );
    }
    return false;
  }
}
