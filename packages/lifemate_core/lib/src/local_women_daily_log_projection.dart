import 'local_mutation_outbox.dart';

/// Deterministic owner-only overlay for Women Health daily logs while offline.
///
/// Server rows stay canonical. Pending/retryable local writes are projected on
/// top for immediate owner continuity; conflicts never silently overwrite the
/// server row and are surfaced separately. Rejected mutations are ignored.
final class LifeMateWomenDailyLogProjection {
  const LifeMateWomenDailyLogProjection._();

  static LifeMateWomenDailyLogProjectionResult project({
    required Iterable<Map<String, dynamic>> serverRows,
    required Iterable<LifeMateDurableMutation> pendingMutations,
    required DateTime fromDate,
    required DateTime toDate,
  }) {
    final from = _dateOnly(fromDate);
    final to = _dateOnly(toDate);
    if (to.isBefore(from)) throw ArgumentError.value(toDate, 'toDate');

    final rowsByDate = <String, Map<String, dynamic>>{};
    for (final raw in serverRows) {
      final row = Map<String, dynamic>.from(raw);
      final date = _requireDate(row['loggedOn'], 'server loggedOn');
      if (!_inRange(date, from, to)) continue;
      rowsByDate[_dateText(date)] = Map<String, dynamic>.unmodifiable(row);
    }

    final ordered = pendingMutations.toList(growable: false)
      ..sort((a, b) {
        final byTime = a.createdAtUtc.compareTo(b.createdAtUtc);
        return byTime != 0 ? byTime : a.mutationId.compareTo(b.mutationId);
      });

    final pendingDates = <String>{};
    final pendingDeletedDates = <String>{};
    final conflictDates = <String>{};

    for (final mutation in ordered) {
      if (!_isDailyLogMutation(mutation)) continue;
      final loggedOn = _requireDate(
        mutation.payload['loggedOn'],
        'pending loggedOn',
      );
      if (!_inRange(loggedOn, from, to)) continue;
      final dateKey = _dateText(loggedOn);

      switch (mutation.state) {
        case LifeMateMutationSyncState.rejected:
          continue;
        case LifeMateMutationSyncState.conflict:
          conflictDates.add(dateKey);
          continue;
        case LifeMateMutationSyncState.pending:
        case LifeMateMutationSyncState.retryScheduled:
          break;
      }

      pendingDates.add(dateKey);
      final isDelete = mutation.payload['delete'] == true;
      if (isDelete) {
        final version = _nonNegativeInt(mutation.payload['version'], 'version');
        if (version <= 0) {
          throw const FormatException(
            'Pending Women Health delete requires canonical revision.',
          );
        }
        rowsByDate.remove(dateKey);
        pendingDeletedDates.add(dateKey);
        continue;
      }

      final payload = Map<String, dynamic>.from(mutation.payload);
      _nonNegativeInt(payload['version'], 'version');
      rowsByDate[dateKey] = Map<String, dynamic>.unmodifiable(<String, dynamic>{
        ...payload,
        'pendingSync': true,
        'serverConfirmed': false,
        'localMutationId': mutation.mutationId,
      });
      pendingDeletedDates.remove(dateKey);
    }

    final rows = rowsByDate.values.toList(growable: false)
      ..sort(
        (a, b) => a['loggedOn'].toString().compareTo(b['loggedOn'].toString()),
      );

    return LifeMateWomenDailyLogProjectionResult(
      rows: List<Map<String, dynamic>>.unmodifiable(rows),
      pendingDates: Set<String>.unmodifiable(pendingDates),
      pendingDeletedDates: Set<String>.unmodifiable(pendingDeletedDates),
      conflictDates: Set<String>.unmodifiable(conflictDates),
    );
  }

  static bool _isDailyLogMutation(LifeMateDurableMutation mutation) =>
      mutation.domain == LifeMateMutationDomain.womenHealth &&
      mutation.method == 'PUT' &&
      mutation.endpointPath == '/api/v1/women-calendar/daily-logs' &&
      mutation.sourceKey.startsWith('women-daily-log:');

  static int _nonNegativeInt(Object? value, String field) {
    final parsed = value is int ? value : int.tryParse(value?.toString() ?? '');
    if (parsed == null || parsed < 0) {
      throw FormatException('Invalid Women Health $field.');
    }
    return parsed;
  }

  static DateTime _requireDate(Object? value, String field) {
    final text = value?.toString() ?? '';
    final parsed = DateTime.tryParse(text);
    if (parsed == null || text.length != 10) {
      throw FormatException('Invalid Women Health $field.');
    }
    return _dateOnly(parsed);
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);
  static bool _inRange(DateTime value, DateTime from, DateTime to) =>
      !value.isBefore(from) && !value.isAfter(to);
  static String _dateText(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

final class LifeMateWomenDailyLogProjectionResult {
  const LifeMateWomenDailyLogProjectionResult({
    required this.rows,
    required this.pendingDates,
    required this.pendingDeletedDates,
    required this.conflictDates,
  });

  final List<Map<String, dynamic>> rows;
  final Set<String> pendingDates;
  final Set<String> pendingDeletedDates;
  final Set<String> conflictDates;

  bool get hasPending => pendingDates.isNotEmpty;
  bool get hasConflict => conflictDates.isNotEmpty;
}
