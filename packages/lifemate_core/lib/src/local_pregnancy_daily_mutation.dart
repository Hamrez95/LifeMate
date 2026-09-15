import 'local_health_store.dart' show LifeMateLocalNamespace;
import 'local_mutation_outbox.dart';

/// Durable owner-entered pregnancy daily captures for Cocoon offline replay.
///
/// This primitive mirrors the existing canonical pregnancy capture API only.
/// It reuses the shared owner-health mutation replay policy while retaining
/// pregnancy-specific source keys and endpoints; it does not create another
/// queue or source of truth. It does not infer symptoms, diagnoses, safety
/// classifications or sharing. Authentication credentials are never persisted.
final class LifeMateOfflinePregnancyDailyMutation {
  LifeMateOfflinePregnancyDailyMutation._();

  static final RegExp _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  );
  static final RegExp _symptomCode = RegExp(r'^[a-z0-9][a-z0-9._-]{1,63}$');

  static const Set<String> _feelings = <String>{
    'comfortable',
    'mixed',
    'difficult',
  };
  static const Set<String> _energy = <String>{'low', 'steady', 'high'};
  static const Set<String> _intensities = <String>{
    'mild',
    'moderate',
    'strong',
  };
  static const Set<String> _moods = <String>{
    'very_low',
    'low',
    'neutral',
    'good',
    'very_good',
  };

  static Future<LifeMateDurableMutation> enqueueCheckIn({
    required LifeMateLocalMutationOutbox outbox,
    required LifeMateLocalNamespace namespace,
    required String mutationId,
    required DateTime observedAtUtc,
    required DateTime localDate,
    required String timeZone,
    required String feeling,
    required String energy,
    DateTime? createdAtUtc,
  }) async {
    final mutation = buildCheckIn(
      mutationId: mutationId,
      observedAtUtc: observedAtUtc,
      localDate: localDate,
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
    required DateTime observedAtUtc,
    required DateTime localDate,
    required String timeZone,
    required String feeling,
    required String energy,
    DateTime? createdAtUtc,
  }) {
    final requestId = _requestId(mutationId);
    final zone = _required(timeZone, 'timeZone');
    final normalizedFeeling = _oneOf(feeling, 'feeling', _feelings);
    final normalizedEnergy = _oneOf(energy, 'energy', _energy);
    return _build(
      mutationId: requestId,
      sourceKey: 'pregnancy-check-in:${_dateText(localDate)}',
      endpointPath: '/api/v1/cocoon/pregnancy/check-ins',
      observedAtUtc: observedAtUtc,
      localDate: localDate,
      timeZone: zone,
      createdAtUtc: createdAtUtc,
      extraPayload: <String, dynamic>{
        'feeling': normalizedFeeling,
        'energy': normalizedEnergy,
      },
    );
  }

  static Future<LifeMateDurableMutation> enqueueSymptom({
    required LifeMateLocalMutationOutbox outbox,
    required LifeMateLocalNamespace namespace,
    required String mutationId,
    required DateTime observedAtUtc,
    required DateTime localDate,
    required String timeZone,
    required String symptomCode,
    required String intensity,
    String? note,
    DateTime? createdAtUtc,
  }) async {
    final mutation = buildSymptom(
      mutationId: mutationId,
      observedAtUtc: observedAtUtc,
      localDate: localDate,
      timeZone: timeZone,
      symptomCode: symptomCode,
      intensity: intensity,
      note: note,
      createdAtUtc: createdAtUtc,
    );
    await outbox.enqueue(namespace: namespace, mutation: mutation);
    return mutation;
  }

  static LifeMateDurableMutation buildSymptom({
    required String mutationId,
    required DateTime observedAtUtc,
    required DateTime localDate,
    required String timeZone,
    required String symptomCode,
    required String intensity,
    String? note,
    DateTime? createdAtUtc,
  }) {
    final requestId = _requestId(mutationId);
    final zone = _required(timeZone, 'timeZone');
    final code = symptomCode.trim().toLowerCase();
    if (!_symptomCode.hasMatch(code)) {
      throw ArgumentError.value(symptomCode, 'symptomCode');
    }
    final normalizedIntensity = _oneOf(intensity, 'intensity', _intensities);
    final normalizedNote = _optionalLimited(note, 'note', 400);
    return _build(
      mutationId: requestId,
      sourceKey: 'pregnancy-symptom:$requestId',
      endpointPath: '/api/v1/cocoon/pregnancy/symptoms',
      observedAtUtc: observedAtUtc,
      localDate: localDate,
      timeZone: zone,
      createdAtUtc: createdAtUtc,
      extraPayload: <String, dynamic>{
        'symptomCode': code,
        'intensity': normalizedIntensity,
        if (normalizedNote != null) 'note': normalizedNote,
      },
    );
  }

  static Future<LifeMateDurableMutation> enqueueMood({
    required LifeMateLocalMutationOutbox outbox,
    required LifeMateLocalNamespace namespace,
    required String mutationId,
    required DateTime observedAtUtc,
    required DateTime localDate,
    required String timeZone,
    required String moodCode,
    DateTime? createdAtUtc,
  }) async {
    final mutation = buildMood(
      mutationId: mutationId,
      observedAtUtc: observedAtUtc,
      localDate: localDate,
      timeZone: timeZone,
      moodCode: moodCode,
      createdAtUtc: createdAtUtc,
    );
    await outbox.enqueue(namespace: namespace, mutation: mutation);
    return mutation;
  }

  static LifeMateDurableMutation buildMood({
    required String mutationId,
    required DateTime observedAtUtc,
    required DateTime localDate,
    required String timeZone,
    required String moodCode,
    DateTime? createdAtUtc,
  }) {
    final requestId = _requestId(mutationId);
    final zone = _required(timeZone, 'timeZone');
    final normalizedMood = _oneOf(moodCode, 'moodCode', _moods);
    return _build(
      mutationId: requestId,
      sourceKey: 'pregnancy-mood:$requestId',
      endpointPath: '/api/v1/cocoon/pregnancy/moods',
      observedAtUtc: observedAtUtc,
      localDate: localDate,
      timeZone: zone,
      createdAtUtc: createdAtUtc,
      extraPayload: <String, dynamic>{'moodCode': normalizedMood},
    );
  }

  static LifeMateDurableMutation _build({
    required String mutationId,
    required String sourceKey,
    required String endpointPath,
    required DateTime observedAtUtc,
    required DateTime localDate,
    required String timeZone,
    required Map<String, dynamic> extraPayload,
    DateTime? createdAtUtc,
  }) {
    final observed = observedAtUtc.toUtc();
    final created = (createdAtUtc ?? DateTime.now().toUtc()).toUtc();
    return LifeMateDurableMutation(
      mutationId: mutationId,
      domain: LifeMateMutationDomain.healthObservation,
      sourceKey: sourceKey,
      method: 'POST',
      endpointPath: endpointPath,
      payload: <String, dynamic>{
        'clientRequestId': mutationId,
        'observedAtUtc': observed.toIso8601String(),
        'localDate': _dateText(localDate),
        'timeZone': timeZone,
        ...extraPayload,
      },
      createdAtUtc: created,
      timeZone: timeZone,
    );
  }

  static String _requestId(String value) {
    final normalized = value.trim().toLowerCase();
    if (!_uuid.hasMatch(normalized)) {
      throw ArgumentError.value(value, 'mutationId');
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

  static String _oneOf(String value, String field, Set<String> allowed) {
    final normalized = value.trim().toLowerCase();
    if (!allowed.contains(normalized)) {
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
