import 'local_health_store.dart' show LifeMateLocalNamespace;
import 'local_mutation_outbox.dart';

/// Builds and enqueues exact treatment mutations that may be accepted into the
/// protected #831 outbox when the owner has complete locally validated inputs.
///
/// This deliberately does not make clinical timing decisions, shorten or
/// lengthen medication intervals, infer missing fields, or bypass server
/// conflict/idempotency checks. Offline create is intentionally bounded to an
/// already-known medication plus explicit weekday/time schedules; recurrence
/// creation remains online-only until its full validation/projection contract
/// can be proven locally.
final class LifeMateOfflineTreatmentMutation {
  LifeMateOfflineTreatmentMutation._();

  static final RegExp _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );
  static final RegExp _idempotencyKey = RegExp(r'^[A-Za-z0-9._:-]{8,180}$');
  static final RegExp _localTime = RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$');
  static const _weekdays = <String>{
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
  };
  static const _statuses = <String>{'active', 'stopped'};
  static const _maximumReminderLeadMinutes = 7 * 24 * 60;

  /// Validates a bounded create first and only then writes it to the protected
  /// outbox. The server receives the same stable mutation ID as Idempotency-Key
  /// during replay, so reconnect can retry the POST without duplicating a plan.
  static Future<LifeMateDurableMutation> enqueueCreate({
    required LifeMateLocalMutationOutbox outbox,
    required LifeMateLocalNamespace namespace,
    required String mutationId,
    required String medicationId,
    required String doseText,
    String? instructions,
    required DateTime startDate,
    DateTime? endDate,
    required String timeZone,
    required List<Map<String, String>> schedules,
    required int patientReminderMinutesBefore,
    required int caregiverReminderMinutesBefore,
    DateTime? createdAtUtc,
  }) async {
    final mutation = buildCreate(
      mutationId: mutationId,
      medicationId: medicationId,
      doseText: doseText,
      instructions: instructions,
      startDate: startDate,
      endDate: endDate,
      timeZone: timeZone,
      schedules: schedules,
      patientReminderMinutesBefore: patientReminderMinutesBefore,
      caregiverReminderMinutesBefore: caregiverReminderMinutesBefore,
      createdAtUtc: createdAtUtc,
    );
    await outbox.enqueue(namespace: namespace, mutation: mutation);
    return mutation;
  }

  /// Builds only the locally safe subset of treatment creation: an existing
  /// medication ID, exact dates/timezone, explicit weekday/time schedules and
  /// explicit reminder lead times. Recurrence is fixed to disabled and is never
  /// inferred from local inputs.
  static LifeMateDurableMutation buildCreate({
    required String mutationId,
    required String medicationId,
    required String doseText,
    String? instructions,
    required DateTime startDate,
    DateTime? endDate,
    required String timeZone,
    required List<Map<String, String>> schedules,
    required int patientReminderMinutesBefore,
    required int caregiverReminderMinutesBefore,
    DateTime? createdAtUtc,
  }) {
    final normalizedMutationId = mutationId.trim();
    if (!_idempotencyKey.hasMatch(normalizedMutationId)) {
      throw ArgumentError.value(mutationId, 'mutationId');
    }
    final normalizedMedicationId = medicationId.trim();
    if (!_uuid.hasMatch(normalizedMedicationId)) {
      throw ArgumentError.value(medicationId, 'medicationId');
    }
    final normalizedDoseText = _required(doseText, 'doseText');
    final normalizedTimeZone = _required(timeZone, 'timeZone');
    _validateReminderLead(
      patientReminderMinutesBefore,
      'patientReminderMinutesBefore',
    );
    _validateReminderLead(
      caregiverReminderMinutesBefore,
      'caregiverReminderMinutesBefore',
    );

    final start = _dateOnly(startDate);
    final end = endDate == null ? null : _dateOnly(endDate);
    if (end != null && end.isBefore(start)) {
      throw ArgumentError.value(endDate, 'endDate');
    }
    final normalizedSchedules = _normalizeSchedules(schedules);
    final created = (createdAtUtc ?? DateTime.now().toUtc()).toUtc();

    return LifeMateDurableMutation(
      mutationId: normalizedMutationId,
      domain: LifeMateMutationDomain.treatment,
      sourceKey: 'pending-treatment-create:$normalizedMutationId',
      method: 'POST',
      endpointPath: '/api/v1/treatment-plans',
      payload: <String, dynamic>{
        'medicationId': normalizedMedicationId,
        'doseText': normalizedDoseText,
        'instructions': _emptyToNull(instructions),
        'startDate': _dateText(start),
        'endDate': end == null ? null : _dateText(end),
        'timeZone': normalizedTimeZone,
        'schedules': normalizedSchedules,
        'recurrence': const <String, dynamic>{'version': 2, 'enabled': false},
        'recurrenceStartLocalTime': null,
        'patientReminderMinutesBefore': patientReminderMinutesBefore,
        'caregiverReminderMinutesBefore': caregiverReminderMinutesBefore,
      },
      createdAtUtc: created,
      timeZone: normalizedTimeZone,
    );
  }

  /// Validates the complete edit first and only then writes it to the durable
  /// protected outbox. A validation failure therefore cannot leave a partial
  /// or malformed treatment mutation behind.
  static Future<LifeMateDurableMutation> enqueueEdit({
    required LifeMateLocalMutationOutbox outbox,
    required LifeMateLocalNamespace namespace,
    required String mutationId,
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
    DateTime? createdAtUtc,
  }) async {
    final mutation = buildEdit(
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
      createdAtUtc: createdAtUtc,
    );
    await outbox.enqueue(namespace: namespace, mutation: mutation);
    return mutation;
  }

  static LifeMateDurableMutation buildEdit({
    required String mutationId,
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
    DateTime? createdAtUtc,
  }) {
    final planId = treatmentPlanId.trim();
    if (!_uuid.hasMatch(planId)) {
      throw ArgumentError.value(treatmentPlanId, 'treatmentPlanId');
    }
    if (version <= 0) throw ArgumentError.value(version, 'version');
    if (medicationVersion <= 0) {
      throw ArgumentError.value(medicationVersion, 'medicationVersion');
    }
    final normalizedMedicationName = _required(
      medicationName,
      'medicationName',
    );
    final normalizedDoseText = _required(doseText, 'doseText');
    final normalizedTimeZone = _required(timeZone, 'timeZone');
    final normalizedStatus = status.trim().toLowerCase();
    if (!_statuses.contains(normalizedStatus)) {
      throw ArgumentError.value(status, 'status');
    }
    _validateReminderLead(
      patientReminderMinutesBefore,
      'patientReminderMinutesBefore',
    );
    _validateReminderLead(
      caregiverReminderMinutesBefore,
      'caregiverReminderMinutesBefore',
    );

    final start = _dateOnly(startDate);
    final end = endDate == null ? null : _dateOnly(endDate);
    if (end != null && end.isBefore(start)) {
      throw ArgumentError.value(endDate, 'endDate');
    }

    final normalizedSchedules = _normalizeSchedules(schedules);
    final created = (createdAtUtc ?? DateTime.now().toUtc()).toUtc();
    return LifeMateDurableMutation(
      mutationId: mutationId,
      domain: LifeMateMutationDomain.treatment,
      sourceKey: planId,
      method: 'PATCH',
      endpointPath: '/api/v1/treatment-plans/$planId',
      payload: <String, dynamic>{
        'version': version,
        'medicationVersion': medicationVersion,
        'medicationName': normalizedMedicationName,
        'strengthText': _emptyToNull(strengthText),
        'form': _emptyToNull(form),
        'doseText': normalizedDoseText,
        'instructions': _emptyToNull(instructions),
        'startDate': _dateText(start),
        'endDate': end == null ? null : _dateText(end),
        'timeZone': normalizedTimeZone,
        'schedules': normalizedSchedules,
        'patientReminderMinutesBefore': patientReminderMinutesBefore,
        'caregiverReminderMinutesBefore': caregiverReminderMinutesBefore,
        'status': normalizedStatus,
      },
      createdAtUtc: created,
      timeZone: normalizedTimeZone,
      expectedRevision: version.toString(),
    );
  }

  static List<Map<String, String>> _normalizeSchedules(
    List<Map<String, String>> schedules,
  ) {
    final normalized = schedules
        .map<Map<String, String>>((schedule) {
          final day = schedule['dayOfWeek']?.trim().toLowerCase() ?? '';
          final localTime = schedule['localTime']?.trim() ?? '';
          if (!_weekdays.contains(day) || !_localTime.hasMatch(localTime)) {
            throw ArgumentError.value(schedule, 'schedules');
          }
          return <String, String>{'dayOfWeek': day, 'localTime': localTime};
        })
        .toList(growable: false);
    if (normalized.isEmpty) {
      throw ArgumentError.value(schedules, 'schedules');
    }
    return normalized;
  }

  static String _required(String value, String field) {
    final normalized = value.trim();
    if (normalized.isEmpty) throw ArgumentError.value(value, field);
    return normalized;
  }

  static String? _emptyToNull(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

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
