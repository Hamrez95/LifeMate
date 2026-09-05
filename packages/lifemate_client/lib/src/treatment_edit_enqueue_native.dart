import 'package:lifemate_core/lifemate_core.dart';

Future<String> enqueueTreatmentPlanEdit({
  required String environmentId,
  required String accountId,
  required String personId,
  required String treatmentPlanId,
  required int version,
  required int medicationVersion,
  required String medicationName,
  String? strengthText,
  String? form,
  required String doseText,
  String? instructions,
  required DateTime startDate,
  DateTime? endDate,
  required String timeZone,
  required List<Map<String, String>> schedules,
  required int patientReminderMinutesBefore,
  required int caregiverReminderMinutesBefore,
  required String status,
  required String mutationId,
  Object? localStore,
}) async {
  if (localStore != null && localStore is! LifeMateLocalHealthStore) {
    throw ArgumentError.value(localStore, 'localStore');
  }

  final ownsStore = localStore == null;
  final store = localStore is LifeMateLocalHealthStore
      ? localStore
      : await LifeMateLocalHealthStore.openDefault();
  try {
    final outbox = LifeMateLocalMutationOutbox(store: store);
    final mutation = await LifeMateOfflineTreatmentMutation.enqueueEdit(
      outbox: outbox,
      namespace: LifeMateLocalNamespace(
        environmentId: environmentId,
        accountId: accountId,
        personId: personId,
      ),
      mutationId: mutationId,
      treatmentPlanId: treatmentPlanId,
      version: version,
      medicationVersion: medicationVersion,
      medicationName: medicationName,
      strengthText: strengthText,
      form: form,
      doseText: doseText,
      instructions: instructions,
      startDate: startDate,
      endDate: endDate,
      timeZone: timeZone,
      schedules: schedules,
      patientReminderMinutesBefore: patientReminderMinutesBefore,
      caregiverReminderMinutesBefore: caregiverReminderMinutesBefore,
      status: status,
    );
    return mutation.mutationId;
  } finally {
    if (ownsStore) store.close();
  }
}
