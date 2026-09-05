import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

typedef WellMateOfflineCareEventCreateEnqueuer = Future<void> Function(
  WellMateOfflineCareEventCreateRequest request,
);

enum WellMateCareEventSaveState { serverConfirmed, pendingSync }

class WellMateOfflineCareEventCreateRequest {
  const WellMateOfflineCareEventCreateRequest({
    required this.clientRequestId,
    required this.eventType,
    required this.title,
    required this.providerName,
    required this.specialty,
    required this.medicationName,
    required this.doseText,
    required this.administrationRoute,
    required this.reason,
    required this.instructions,
    required this.centerName,
    required this.addressLine,
    required this.phoneNumber,
    required this.scheduledLocalDate,
    required this.scheduledLocalTime,
    required this.timeZone,
    required this.patientReminderMinutesBefore,
    required this.caregiverReminderMinutesBefore,
  });

  final String clientRequestId;
  final String eventType;
  final String title;
  final String? providerName;
  final String? specialty;
  final String? medicationName;
  final String? doseText;
  final String? administrationRoute;
  final String? reason;
  final String? instructions;
  final String? centerName;
  final String? addressLine;
  final String? phoneNumber;
  final DateTime scheduledLocalDate;
  final String scheduledLocalTime;
  final String timeZone;
  final int patientReminderMinutesBefore;
  final int caregiverReminderMinutesBefore;
}

bool canQueueCareEventCreateOffline(LifeMateApiException error) =>
    !kIsWeb &&
    const <String>{
      'network_unavailable',
      'network_timeout',
      'retry_budget_exhausted',
    }.contains(error.code);

Future<bool> tryQueueCareEventCreateOffline(
  BuildContext context,
  WellMateOfflineCareEventCreateRequest request, {
  WellMateOfflineCareEventCreateEnqueuer? injectedEnqueuer,
}) async {
  if (kIsWeb) return false;
  try {
    if (injectedEnqueuer != null) {
      await injectedEnqueuer(request);
      return true;
    }
    final apiClient = context.read<LifeMateApiClient>();
    if (apiClient is! DurableLifeMateApiClient) return false;
    await apiClient.enqueueOfflineCareEventCreate(
      clientRequestId: request.clientRequestId,
      eventType: request.eventType,
      title: request.title,
      providerName: request.providerName,
      specialty: request.specialty,
      medicationName: request.medicationName,
      doseText: request.doseText,
      administrationRoute: request.administrationRoute,
      reason: request.reason,
      instructions: request.instructions,
      centerName: request.centerName,
      addressLine: request.addressLine,
      phoneNumber: request.phoneNumber,
      scheduledLocalDate: request.scheduledLocalDate,
      scheduledLocalTime: request.scheduledLocalTime,
      timeZone: request.timeZone,
      patientReminderMinutesBefore: request.patientReminderMinutesBefore,
      caregiverReminderMinutesBefore: request.caregiverReminderMinutesBefore,
    );
    return true;
  } catch (error) {
    if (kDebugMode) {
      debugPrint(
        'Offline care-event create enqueue unavailable: ${error.runtimeType}',
      );
    }
    return false;
  }
}
