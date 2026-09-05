import 'package:lifemate_client/lifemate_client.dart';

Future<LifeMateTreatmentReconnectResult?>
reconcileOwnerTreatmentAfterReconnectIfSupported({
  required LifeMateApiClient apiClient,
  required DateTime fromDate,
  required DateTime toDate,
  required LifeMateTreatmentReminderReconciler reconcileReminders,
}) async {
  if (apiClient is! DurableLifeMateApiClient) return null;
  return apiClient.reconcileTreatmentAfterReconnect(
    fromDate: fromDate,
    toDate: toDate,
    reconcileReminders: reconcileReminders,
  );
}
