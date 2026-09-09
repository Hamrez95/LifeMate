import 'local_health_store.dart' show LifeMateLocalNamespace;
import 'local_mutation_outbox.dart';

/// Durable owner-only pregnancy tracking writes for native offline continuity.
///
/// `healthObservation` is intentionally reused only as the additive outbox
/// conflict class. Canonical persistence remains in the bounded `pregnancy`
/// server domain; this adapter never turns these captures into generic
/// `lifemate.health_observations` rows and never performs clinical inference.
final class LifeMateOfflinePregnancyTrackingMutation {
  LifeMateOfflinePregnancyTrackingMutation._();

  static final RegExp _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  );
  static final RegExp _symptomCode = RegExp(r'^[a-z][a-z0-9_]{1,63}$');
  static const Set<String> _feelings = <String>{
    'comfortable',
    'mixed',
    'difficult',
  };
  static const Set<String> _energy = <String>{'low', 'steady', 'high'};
  static const Set<String> _intensity = <String>{'mild', 'moderate', 'strong'};

  static Future<LifeMateDurableMutation> enqueueCheckIn({
    required LifeMateLocalMutationOutbox outbox,
    required LifeMateLocalNamespace namespace,
    required String mutationId,
    required DateTime loggedLocalDate,
    required String timeZone,
    required String feeling,
    required String energy,
    DateTime? createdAtUtc,
  }) async {
    final mutation = buildCheckIn(
      mutationId: mutationId,
      loggedLocalDate: loggedLocalDate,
      timeZone: timeZone,
      feeling: feeling,
      energy: energy,
      createdAtUtc: createdAtUtc,
    );
    await outbox.enqueue(namespace: namespace, mutation: mutation);
    return mutation;
  }

  static LifeMateDurableMutation buildCheckIn({
    required String mutationId,
    required DateTime loggedLocalDate,
    required String timeZone,
    required String feeling,
    required String energy,
    DateTime? createdAtUtc,
  }) {
    final id = _mutationId(mutationId);
    final date = _dateText(loggedLocalDate);
    final zone = _required(timeZone, 'timeZone');
    final normalizedFeeling = _enumValue(feeling, 'feeling', _feelings);
    final normalizedEnergy = _enumValue(energy, 'energy', _energy);
    final created = (createdAtUtc ?? DateTime.now().toUtc()).toUtc();
    return LifeMateDurableMutation(
      mutationId: id,
      domain: LifeMateMutationDomain.healthObservation,
      sourceKey: 'pregnancy-check-in:$date',
      method: 'POST',
      endpointPath: '/api/v1/cocoon/pregnancy/check-ins',
      payload: <String, dynamic>{
        'clientRequestId': id,
        'loggedLocalDate': date,
        'timeZone': zone,
        'feeling': normalizedFeeling,
        'energy': normalizedEnergy,
      },
      createdAtUtc: created,
      timeZone: zone,
    );
  }

  static Future<LifeMateDurableMutation> enqueueSymptom({
    required LifeMateLocalMutationOutbox outbox,
    required LifeMateLocalNamespace namespace,
    required String mutationId,
    required String symptomCode,
    required String intensity,
    required DateTime observedAtUtc,
    required DateTime observedLocalDate,
    required String timeZone,
    String? note,
    DateTime? createdAtUtc,
  }) async {
    final mutation = buildSymptom(
      mutationId: mutationId,
      symptomCode: symptomCode,
      intensity: intensity,
      observedAtUtc: observedAtUtc,
      observedLocalDate: observedLocalDate,
      timeZone: timeZone,
      note: note,
      createdAtUtc: createdAtUtc,
    );
    await outbox.enqueue(namespace: namespace, mutation: mutation);
    return mutation;
  }

  static LifeMateDurableMutation buildSymptom({
    required String mutationId,
    required String symptomCode,
    required String intensity,
    required DateTime observedAtUtc,
    required DateTime observedLocalDate,
    required String timeZone,
    String? note,
    DateTime? createdAtUtc,
  }) {
    final id = _mutationId(mutationId);
    final code = symptomCode.trim().toLowerCase();
    if (!_symptomCode.hasMatch(code)) {
      throw ArgumentError.value(symptomCode, 'symptomCode');
    }
    final normalizedIntensity = _enumValue(
      intensity,
      'intensity',
      _intensity,
    );
    if (!observedAtUtc.isUtc) {
      throw ArgumentError.value(observedAtUtc, 'observedAtUtc');
    }
    final date = _dateText(observedLocalDate);
    final zone = _required(timeZone, 'timeZone');
    final normalizedNote = _optionalNote(note);
    final created = (createdAtUtc ?? DateTime.now().toUtc()).toUtc();
    return LifeMateDurableMutation(
      mutationId: id,
      domain: LifeMateMutationDomain.healthObservation,
      sourceKey: 'pregnancy-symptom:$id',
      method: 'POST',
      endpointPath: '/api/v1/cocoon/pregnancy/symptoms',
      payload: <String, dynamic>{
        'clientRequestId': id,
        'symptomCode': code,
        'intensity': normalizedIntensity,
        'note': normalizedNote,
        'observedAtUtc': observedAtUtc.toIso8601String(),
        'observedLocalDate': date,
        'timeZone': zone,
      },
      createdAtUtc: created,
      timeZone: zone,
    );
  }

  static String _mutationId(String value) {
    final normalized = value.trim();
    if (!_uuid.hasMatch(normalized)) {
      throw ArgumentError.value(value, 'mutationId');
    }
    return normalized;
  }

  static String _enumValue(String value, String field, Set<String> allowed) {
    final normalized = value.trim().toLowerCase();
    if (!allowed.contains(normalized)) {
      throw ArgumentError.value(value, field);
    }
    return normalized;
  }

  static String _required(String value, String field) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized.length > 64) {
      throw ArgumentError.value(value, field);
    }
    return normalized;
  }

  static String? _optionalNote(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    if (normalized.length > 400) throw ArgumentError.value(value, 'note');
    return normalized;
  }

  static String _dateText(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
