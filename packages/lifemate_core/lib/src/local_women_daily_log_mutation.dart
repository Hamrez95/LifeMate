import 'local_health_store.dart' show LifeMateLocalNamespace;
import 'local_mutation_outbox.dart';

/// Exact owner daily-log mutations for Women Health offline continuity.
///
/// This type only serializes fields already chosen by the owner. It does not
/// infer symptoms, period state, pregnancy state, sharing, or clinical advice.
/// Authentication credentials are never persisted with the mutation.
final class LifeMateOfflineWomenDailyLogMutation {
  LifeMateOfflineWomenDailyLogMutation._();

  static final RegExp _idempotencyKey = RegExp(r'^[A-Za-z0-9._:-]{8,180}$');
  static const Set<String> _allowedMoods = <String>{
    'great',
    'good',
    'neutral',
    'low',
    'overwhelmed',
  };

  static Future<LifeMateDurableMutation> enqueueUpsert({
    required LifeMateLocalMutationOutbox outbox,
    required LifeMateLocalNamespace namespace,
    required String mutationId,
    required DateTime loggedOn,
    required int version,
    required String timeZone,
    String? mood,
    int? energyLevel,
    String? periodFlow,
    String? bloodAppearance,
    String? bloodTexture,
    int? painLevel,
    Set<String> symptoms = const <String>{},
    String? privateNotes,
    DateTime? createdAtUtc,
  }) async {
    final mutation = buildUpsert(
      mutationId: mutationId,
      loggedOn: loggedOn,
      version: version,
      timeZone: timeZone,
      mood: mood,
      energyLevel: energyLevel,
      periodFlow: periodFlow,
      bloodAppearance: bloodAppearance,
      bloodTexture: bloodTexture,
      painLevel: painLevel,
      symptoms: symptoms,
      privateNotes: privateNotes,
      createdAtUtc: createdAtUtc,
    );
    await outbox.enqueue(namespace: namespace, mutation: mutation);
    return mutation;
  }

  static LifeMateDurableMutation buildUpsert({
    required String mutationId,
    required DateTime loggedOn,
    required int version,
    required String timeZone,
    String? mood,
    int? energyLevel,
    String? periodFlow,
    String? bloodAppearance,
    String? bloodTexture,
    int? painLevel,
    Set<String> symptoms = const <String>{},
    String? privateNotes,
    DateTime? createdAtUtc,
  }) {
    if (version < 0) throw ArgumentError.value(version, 'version');
    final normalizedMood = mood == null ? null : _normalizeMood(mood);
    if (energyLevel != null && (energyLevel < 1 || energyLevel > 5)) {
      throw ArgumentError.value(energyLevel, 'energyLevel');
    }
    // Mirrors lifemate-api women_calendar_rich_period optionalPain(): 0..5.
    if (painLevel != null && (painLevel < 0 || painLevel > 5)) {
      throw ArgumentError.value(painLevel, 'painLevel');
    }
    final key = _mutationId(mutationId);
    final zone = _required(timeZone, 'timeZone');
    final date = _dateText(loggedOn);
    final normalizedSymptoms =
        symptoms
            .map((value) {
              final normalized = value.trim();
              if (normalized.isEmpty) {
                throw ArgumentError.value(value, 'symptoms');
              }
              return normalized;
            })
            .toSet()
            .toList(growable: false)
          ..sort();
    final created = (createdAtUtc ?? DateTime.now().toUtc()).toUtc();

    final normalizedPeriodFlow = _emptyToNull(periodFlow);
    final normalizedBloodAppearance = _emptyToNull(bloodAppearance);
    final normalizedBloodTexture = _emptyToNull(bloodTexture);
    final ownerCheckIn = normalizedMood != null || energyLevel != null;
    if (ownerCheckIn &&
        (normalizedPeriodFlow != null ||
            normalizedBloodAppearance != null ||
            normalizedBloodTexture != null)) {
      throw ArgumentError(
        'Owner check-in and rich period-only fields must be queued separately.',
      );
    }

    final payload = ownerCheckIn
        ? <String, dynamic>{
            'version': version,
            'loggedOn': date,
            if (normalizedMood != null) 'mood': normalizedMood,
            if (energyLevel != null) 'energyLevel': energyLevel,
            'painLevel': painLevel,
            'symptoms': normalizedSymptoms
                .map((value) => value.toLowerCase())
                .toList(growable: false),
            'privateNotes': _emptyToNull(privateNotes),
          }
        : <String, dynamic>{
            'loggedOn': date,
            'version': version,
            'periodFlow': normalizedPeriodFlow,
            'bloodAppearance': normalizedBloodAppearance,
            'bloodTexture': normalizedBloodTexture,
            'painLevel': painLevel,
            'symptoms': normalizedSymptoms,
            'privateNotes': _emptyToNull(privateNotes),
          };

    return LifeMateDurableMutation(
      mutationId: key,
      domain: LifeMateMutationDomain.womenHealth,
      sourceKey: 'women-daily-log:$date',
      method: 'PUT',
      endpointPath: '/api/v1/women-calendar/daily-logs',
      payload: payload,
      createdAtUtc: created,
      timeZone: zone,
      expectedRevision: version > 0 ? version.toString() : null,
    );
  }

  static Future<LifeMateDurableMutation> enqueueDelete({
    required LifeMateLocalMutationOutbox outbox,
    required LifeMateLocalNamespace namespace,
    required String mutationId,
    required DateTime loggedOn,
    required int version,
    required String timeZone,
    DateTime? createdAtUtc,
  }) async {
    final mutation = buildDelete(
      mutationId: mutationId,
      loggedOn: loggedOn,
      version: version,
      timeZone: timeZone,
      createdAtUtc: createdAtUtc,
    );
    await outbox.enqueue(namespace: namespace, mutation: mutation);
    return mutation;
  }

  static LifeMateDurableMutation buildDelete({
    required String mutationId,
    required DateTime loggedOn,
    required int version,
    required String timeZone,
    DateTime? createdAtUtc,
  }) {
    if (version <= 0) throw ArgumentError.value(version, 'version');
    final key = _mutationId(mutationId);
    final zone = _required(timeZone, 'timeZone');
    final date = _dateText(loggedOn);
    final created = (createdAtUtc ?? DateTime.now().toUtc()).toUtc();

    return LifeMateDurableMutation(
      mutationId: key,
      domain: LifeMateMutationDomain.womenHealth,
      sourceKey: 'women-daily-log:$date',
      method: 'PUT',
      endpointPath: '/api/v1/women-calendar/daily-logs',
      payload: <String, dynamic>{
        'loggedOn': date,
        'version': version,
        'delete': true,
      },
      createdAtUtc: created,
      timeZone: zone,
      expectedRevision: version.toString(),
    );
  }

  static String _mutationId(String value) {
    final normalized = value.trim();
    if (!_idempotencyKey.hasMatch(normalized)) {
      throw ArgumentError.value(value, 'mutationId');
    }
    return normalized;
  }

  static String _required(String value, String field) {
    final normalized = value.trim();
    if (normalized.isEmpty) throw ArgumentError.value(value, field);
    return normalized;
  }

  static String _normalizeMood(String value) {
    final normalized = value.trim().toLowerCase();
    if (!_allowedMoods.contains(normalized)) {
      throw ArgumentError.value(value, 'mood');
    }
    return normalized;
  }

  static String? _emptyToNull(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  static String _dateText(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
