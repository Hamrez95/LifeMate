import 'local_care_event_mutation.dart';
import 'local_health_store.dart' show LifeMateLocalNamespace;
import 'local_mutation_outbox.dart';

/// Durable Cocoon pregnancy-calendar creation using the canonical care-event
/// payload and the shared protected outbox.
///
/// Care-event validation remains owned by [LifeMateOfflineCareEventMutation].
/// This wrapper changes only the replay endpoint so the server can create the
/// canonical care event and pregnancy link atomically/idempotently. It never
/// parses presentation labels or creates a second appointment store.
final class LifeMateOfflinePregnancyCalendarMutation {
  LifeMateOfflinePregnancyCalendarMutation._();

  static const Set<String> _classifications = <String>{
    'prenatal',
    'ultrasound',
    'checkup',
    'lab_test',
    'injection',
    'other',
  };

  static Future<LifeMateDurableMutation> enqueueCreate({
    required LifeMateLocalMutationOutbox outbox,
    required LifeMateLocalNamespace namespace,
    required String mutationId,
    required String classification,
    required String eventType,
    required String title,
    String? providerName,
    String? specialty,
    String? medicationName,
    String? doseText,
    String? administrationRoute,
    String? reason,
    String? instructions,
    String? centerName,
    String? addressLine,
    String? phoneNumber,
    required DateTime scheduledLocalDate,
    required String scheduledLocalTime,
    required String timeZone,
    required int patientReminderMinutesBefore,
    required int caregiverReminderMinutesBefore,
    DateTime? createdAtUtc,
  }) async {
    final mutation = buildCreate(
      mutationId: mutationId,
      classification: classification,
      eventType: eventType,
      title: title,
      providerName: providerName,
      specialty: specialty,
      medicationName: medicationName,
      doseText: doseText,
      administrationRoute: administrationRoute,
      reason: reason,
      instructions: instructions,
      centerName: centerName,
      addressLine: addressLine,
      phoneNumber: phoneNumber,
      scheduledLocalDate: scheduledLocalDate,
      scheduledLocalTime: scheduledLocalTime,
      timeZone: timeZone,
      patientReminderMinutesBefore: patientReminderMinutesBefore,
      caregiverReminderMinutesBefore: caregiverReminderMinutesBefore,
      createdAtUtc: createdAtUtc,
    );
    await outbox.enqueue(namespace: namespace, mutation: mutation);
    return mutation;
  }

  static LifeMateDurableMutation buildCreate({
    required String mutationId,
    required String classification,
    required String eventType,
    required String title,
    String? providerName,
    String? specialty,
    String? medicationName,
    String? doseText,
    String? administrationRoute,
    String? reason,
    String? instructions,
    String? centerName,
    String? addressLine,
    String? phoneNumber,
    required DateTime scheduledLocalDate,
    required String scheduledLocalTime,
    required String timeZone,
    required int patientReminderMinutesBefore,
    required int caregiverReminderMinutesBefore,
    DateTime? createdAtUtc,
  }) {
    final normalizedClassification = classification.trim().toLowerCase();
    if (!_classifications.contains(normalizedClassification)) {
      throw ArgumentError.value(classification, 'classification');
    }

    final canonicalCareEvent = LifeMateOfflineCareEventMutation.buildCreate(
      mutationId: mutationId,
      eventType: eventType,
      title: title,
      providerName: providerName,
      specialty: specialty,
      medicationName: medicationName,
      doseText: doseText,
      administrationRoute: administrationRoute,
      reason: reason,
      instructions: instructions,
      centerName: centerName,
      addressLine: addressLine,
      phoneNumber: phoneNumber,
      scheduledLocalDate: scheduledLocalDate,
      scheduledLocalTime: scheduledLocalTime,
      timeZone: timeZone,
      patientReminderMinutesBefore: patientReminderMinutesBefore,
      caregiverReminderMinutesBefore: caregiverReminderMinutesBefore,
      createdAtUtc: createdAtUtc,
    );

    return LifeMateDurableMutation(
      mutationId: canonicalCareEvent.mutationId,
      domain: LifeMateMutationDomain.careEvent,
      sourceKey: 'pregnancy-care-event-create:${canonicalCareEvent.mutationId}',
      method: 'POST',
      endpointPath: '/api/v1/cocoon/pregnancy/calendar/events',
      payload: <String, dynamic>{
        'careEvent': canonicalCareEvent.payload,
        'classification': normalizedClassification,
      },
      createdAtUtc: canonicalCareEvent.createdAtUtc,
      timeZone: canonicalCareEvent.timeZone,
    );
  }
}
