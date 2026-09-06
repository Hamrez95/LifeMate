import 'local_health_store.dart' show LifeMateLocalNamespace;
import 'local_mutation_outbox.dart';

/// Exact owner period-episode mutations for Women Health offline continuity.
///
/// This primitive persists only dates and the owner's private note. It never
/// infers cycle state, pregnancy state, sharing, relationship access, or
/// clinical advice. Server IDs are required for edits; pending creates remain
/// distinct logical actions until canonical reconciliation returns an ID.
final class LifeMateOfflineWomenEpisodeMutation {
  LifeMateOfflineWomenEpisodeMutation._();

  static final RegExp _idempotencyKey = RegExp(r'^[A-Za-z0-9._:-]{8,180}$');
  static final RegExp _opaqueEpisodeId = RegExp(r'^[A-Za-z0-9._:-]{1,180}$');

  static Future<LifeMateDurableMutation> enqueueCreate({
    required LifeMateLocalMutationOutbox outbox,
    required LifeMateLocalNamespace namespace,
    required String mutationId,
    required DateTime startedOn,
    DateTime? endedOn,
    String? privateNotes,
    required String timeZone,
    DateTime? createdAtUtc,
  }) async {
    final mutation = buildCreate(
      mutationId: mutationId,
      startedOn: startedOn,
      endedOn: endedOn,
      privateNotes: privateNotes,
      timeZone: timeZone,
      createdAtUtc: createdAtUtc,
    );
    await outbox.enqueue(namespace: namespace, mutation: mutation);
    return mutation;
  }

  static LifeMateDurableMutation buildCreate({
    required String mutationId,
    required DateTime startedOn,
    DateTime? endedOn,
    String? privateNotes,
    required String timeZone,
    DateTime? createdAtUtc,
  }) {
    final key = _mutationId(mutationId);
    final zone = _required(timeZone, 'timeZone');
    final start = _dateOnly(startedOn);
    final end = endedOn == null ? null : _dateOnly(endedOn);
    if (end != null && end.isBefore(start)) {
      throw ArgumentError.value(endedOn, 'endedOn');
    }
    final created = (createdAtUtc ?? DateTime.now().toUtc()).toUtc();
    return LifeMateDurableMutation(
      mutationId: key,
      domain: LifeMateMutationDomain.womenHealth,
      sourceKey: 'women-episode-create:$key',
      method: 'POST',
      endpointPath: '/api/v1/women-calendar/episodes',
      payload: <String, dynamic>{
        'startedOn': _dateText(start),
        'endedOn': end == null ? null : _dateText(end),
        'privateNotes': _emptyToNull(privateNotes),
      },
      createdAtUtc: created,
      timeZone: zone,
    );
  }

  static Future<LifeMateDurableMutation> enqueueUpdate({
    required LifeMateLocalMutationOutbox outbox,
    required LifeMateLocalNamespace namespace,
    required String mutationId,
    required String episodeId,
    required int version,
    required DateTime startedOn,
    DateTime? endedOn,
    String? privateNotes,
    required String timeZone,
    DateTime? createdAtUtc,
  }) async {
    final mutation = buildUpdate(
      mutationId: mutationId,
      episodeId: episodeId,
      version: version,
      startedOn: startedOn,
      endedOn: endedOn,
      privateNotes: privateNotes,
      timeZone: timeZone,
      createdAtUtc: createdAtUtc,
    );
    await outbox.enqueue(namespace: namespace, mutation: mutation);
    return mutation;
  }

  static LifeMateDurableMutation buildUpdate({
    required String mutationId,
    required String episodeId,
    required int version,
    required DateTime startedOn,
    DateTime? endedOn,
    String? privateNotes,
    required String timeZone,
    DateTime? createdAtUtc,
  }) {
    if (version <= 0) throw ArgumentError.value(version, 'version');
    final key = _mutationId(mutationId);
    final id = _episodeId(episodeId);
    final zone = _required(timeZone, 'timeZone');
    final start = _dateOnly(startedOn);
    final end = endedOn == null ? null : _dateOnly(endedOn);
    if (end != null && end.isBefore(start)) {
      throw ArgumentError.value(endedOn, 'endedOn');
    }
    final created = (createdAtUtc ?? DateTime.now().toUtc()).toUtc();
    return LifeMateDurableMutation(
      mutationId: key,
      domain: LifeMateMutationDomain.womenHealth,
      sourceKey: 'women-episode:$id',
      method: 'PATCH',
      endpointPath: '/api/v1/women-calendar/episodes/$id',
      payload: <String, dynamic>{
        'version': version,
        'startedOn': _dateText(start),
        'endedOn': end == null ? null : _dateText(end),
        'privateNotes': _emptyToNull(privateNotes),
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

  static String _episodeId(String value) {
    final normalized = value.trim();
    if (!_opaqueEpisodeId.hasMatch(normalized) || normalized.contains('/')) {
      throw ArgumentError.value(value, 'episodeId');
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
}
