import 'local_health_store.dart' show LifeMateLocalNamespace;
import 'local_mutation_outbox.dart';

/// Durable Cocoon pregnancy measurement creation over the canonical
/// `lifemate.health_observations` contract.
///
/// The outbox stores only the exact owner-entered canonical observation input.
/// It does not create a pregnancy-specific measurement source of truth and does
/// not derive clinical thresholds or interpretation.
final class LifeMateOfflinePregnancyMeasurementMutation {
  LifeMateOfflinePregnancyMeasurementMutation._();

  static final RegExp _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  );
  static const Set<String> _types = <String>{
    'weight',
    'blood_pressure',
    'blood_glucose',
  };

  static Future<LifeMateDurableMutation> enqueueCreate({
    required LifeMateLocalMutationOutbox outbox,
    required LifeMateLocalNamespace namespace,
    required String mutationId,
    required String observationType,
    required double valuePrimary,
    double? valueSecondary,
    String? note,
    required DateTime observedAtUtc,
    required DateTime observedLocalDate,
    required String timeZone,
    DateTime? createdAtUtc,
  }) async {
    final mutation = buildCreate(
      mutationId: mutationId,
      observationType: observationType,
      valuePrimary: valuePrimary,
      valueSecondary: valueSecondary,
      note: note,
      observedAtUtc: observedAtUtc,
      observedLocalDate: observedLocalDate,
      timeZone: timeZone,
      createdAtUtc: createdAtUtc,
    );
    await outbox.enqueue(namespace: namespace, mutation: mutation);
    return mutation;
  }

  static LifeMateDurableMutation buildCreate({
    required String mutationId,
    required String observationType,
    required double valuePrimary,
    double? valueSecondary,
    String? note,
    required DateTime observedAtUtc,
    required DateTime observedLocalDate,
    required String timeZone,
    DateTime? createdAtUtc,
  }) {
    final requestId = _requestId(mutationId);
    final type = observationType.trim().toLowerCase();
    if (!_types.contains(type)) {
      throw ArgumentError.value(observationType, 'observationType');
    }
    if (!valuePrimary.isFinite) {
      throw ArgumentError.value(valuePrimary, 'valuePrimary');
    }
    if (valueSecondary != null && !valueSecondary.isFinite) {
      throw ArgumentError.value(valueSecondary, 'valueSecondary');
    }
    _validateValues(type, valuePrimary, valueSecondary);
    final normalizedNote = _optionalLimited(note, 'note', 500);
    final zone = _required(timeZone, 'timeZone', 64);
    final observed = observedAtUtc.toUtc();
    final created = (createdAtUtc ?? DateTime.now().toUtc()).toUtc();

    return LifeMateDurableMutation(
      mutationId: requestId,
      domain: LifeMateMutationDomain.healthObservation,
      sourceKey: 'pending-pregnancy-measurement:$requestId',
      method: 'POST',
      endpointPath: '/api/v1/cocoon/pregnancy/measurements',
      payload: <String, dynamic>{
        'clientRequestId': requestId,
        'observationType': type,
        'valuePrimary': valuePrimary,
        'valueSecondary': valueSecondary,
        'note': normalizedNote,
        'observedAtUtc': observed.toIso8601String(),
        'observedLocalDate': _dateText(observedLocalDate),
        'timeZone': zone,
      },
      createdAtUtc: created,
      timeZone: zone,
    );
  }

  static void _validateValues(String type, double primary, double? secondary) {
    if (type == 'weight') {
      _range(primary, 1, 500, 'valuePrimary');
      if (secondary != null) {
        throw ArgumentError.value(secondary, 'valueSecondary');
      }
      return;
    }
    if (type == 'blood_pressure') {
      _range(primary, 40, 300, 'valuePrimary');
      if (secondary == null) {
        throw ArgumentError.value(secondary, 'valueSecondary');
      }
      _range(secondary, 20, 200, 'valueSecondary');
      if (primary <= secondary) {
        throw ArgumentError(
          'Systolic pressure must exceed diastolic pressure.',
        );
      }
      return;
    }
    _range(primary, 20, 1000, 'valuePrimary');
    if (secondary != null) {
      throw ArgumentError.value(secondary, 'valueSecondary');
    }
  }

  static void _range(
    double value,
    double minimum,
    double maximum,
    String field,
  ) {
    if (value < minimum || value > maximum) {
      throw ArgumentError.value(value, field);
    }
  }

  static String _requestId(String value) {
    final normalized = value.trim().toLowerCase();
    if (!_uuid.hasMatch(normalized)) {
      throw ArgumentError.value(value, 'mutationId');
    }
    return normalized;
  }

  static String _required(String value, String field, int maximum) {
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
}
