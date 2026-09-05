import 'local_health_store.dart' show LifeMateLocalNamespace;
import 'local_mutation_outbox.dart';

/// Builds the locally safe subset of owner care-event creation for the
/// protected durable outbox. Recurring events stay online-only until their
/// complete expansion/notification contract is available locally.
final class LifeMateOfflineCareEventMutation {
  LifeMateOfflineCareEventMutation._();

  static final RegExp _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  );
  static final RegExp _localTime = RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$');
  static const _eventTypes = <String>{'appointment', 'injection'};
  static const _routes = <String>{
    'intramuscular',
    'subcutaneous',
    'intravenous',
    'other',
  };
  static const _maximumReminderLeadMinutes = 7 * 24 * 60;

  static Future<LifeMateDurableMutation> enqueueCreate({
    required LifeMateLocalMutationOutbox outbox,
    required LifeMateLocalNamespace namespace,
    required String mutationId,
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
    final requestId = mutationId.trim().toLowerCase();
    if (!_uuid.hasMatch(requestId)) {
      throw ArgumentError.value(mutationId, 'mutationId');
    }
    final normalizedEventType = eventType.trim().toLowerCase();
    if (!_eventTypes.contains(normalizedEventType)) {
      throw ArgumentError.value(eventType, 'eventType');
    }
    final normalizedTitle = _requiredLimited(title, 'title', 160);
    final normalizedMedicationName = _optionalLimited(
      medicationName,
      'medicationName',
      160,
    );
    if (normalizedEventType == 'injection' &&
        normalizedMedicationName == null) {
      throw ArgumentError.value(medicationName, 'medicationName');
    }
    final normalizedTime = scheduledLocalTime.trim();
    if (!_localTime.hasMatch(normalizedTime)) {
      throw ArgumentError.value(scheduledLocalTime, 'scheduledLocalTime');
    }
    final normalizedTimeZone = _requiredLimited(timeZone, 'timeZone', 120);
    final normalizedRoute = _optionalLimited(
      administrationRoute,
      'administrationRoute',
      40,
    )?.toLowerCase();
    if (normalizedRoute != null && !_routes.contains(normalizedRoute)) {
      throw ArgumentError.value(administrationRoute, 'administrationRoute');
    }
    _validateReminderLead(
      patientReminderMinutesBefore,
      'patientReminderMinutesBefore',
    );
    _validateReminderLead(
      caregiverReminderMinutesBefore,
      'caregiverReminderMinutesBefore',
    );

    final date = DateTime(
      scheduledLocalDate.year,
      scheduledLocalDate.month,
      scheduledLocalDate.day,
    );
    final created = (createdAtUtc ?? DateTime.now().toUtc()).toUtc();

    return LifeMateDurableMutation(
      mutationId: requestId,
      domain: LifeMateMutationDomain.careEvent,
      sourceKey: 'pending-care-event-create:$requestId',
      method: 'POST',
      endpointPath: '/api/v1/care-events',
      payload: <String, dynamic>{
        'clientRequestId': requestId,
        'eventType': normalizedEventType,
        'title': normalizedTitle,
        'providerName': _optionalLimited(providerName, 'providerName', 160),
        'specialty': _optionalLimited(specialty, 'specialty', 120),
        'medicationName': normalizedMedicationName,
        'doseText': _optionalLimited(doseText, 'doseText', 120),
        'administrationRoute': normalizedRoute,
        'reason': _optionalLimited(reason, 'reason', 500),
        'instructions': _optionalLimited(instructions, 'instructions', 1000),
        'centerName': _optionalLimited(centerName, 'centerName', 200),
        'addressLine': _optionalLimited(addressLine, 'addressLine', 500),
        'phoneNumber': _optionalLimited(phoneNumber, 'phoneNumber', 40),
        'scheduledLocalDate': _dateText(date),
        'scheduledLocalTime': normalizedTime,
        'timeZone': normalizedTimeZone,
        'recurrence': const <String, dynamic>{'version': 2, 'enabled': false},
        'patientReminderMinutesBefore': patientReminderMinutesBefore,
        'caregiverReminderMinutesBefore': caregiverReminderMinutesBefore,
      },
      createdAtUtc: created,
      timeZone: normalizedTimeZone,
    );
  }

  static String _requiredLimited(String value, String field, int maximum) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized.length > maximum) {
      throw ArgumentError.value(value, field);
    }
    return normalized;
  }

  static String? _optionalLimited(String? value, String field, int maximum) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    if (normalized.length > maximum) throw ArgumentError.value(value, field);
    return normalized;
  }

  static String _dateText(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static void _validateReminderLead(int value, String field) {
    if (value < 0 || value > _maximumReminderLeadMinutes) {
      throw ArgumentError.value(value, field);
    }
  }
}
