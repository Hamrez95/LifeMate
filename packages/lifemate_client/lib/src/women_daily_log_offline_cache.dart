import 'package:lifemate_core/lifemate_core.dart';

/// Protected cache for server-confirmed owner Women Health daily logs.
///
/// This cache reuses the shared #829 encrypted Account + Person + environment
/// store. A per-day coverage marker distinguishes a confirmed empty server day
/// from a day that has never been synchronized, so offline callers never invent
/// an unknown canonical version.
final class WomenDailyLogOfflineCache {
  WomenDailyLogOfflineCache({
    required LifeMateLocalHealthStore store,
    required LifeMateLocalNamespace namespace,
  }) : _store = store,
       _namespace = namespace,
       _ownsStore = false;

  WomenDailyLogOfflineCache._owned({
    required LifeMateLocalHealthStore store,
    required LifeMateLocalNamespace namespace,
  }) : _store = store,
       _namespace = namespace,
       _ownsStore = true;

  static const _coverageVersion = 1;
  static const _rowPrefix = 'women-daily-log:';
  static const _coveragePrefix = 'women-daily-log-coverage:';
  static const _maxRangeDays = 120;
  static const _allowedMoods = <String>{
    'great',
    'good',
    'neutral',
    'low',
    'overwhelmed',
  };

  final LifeMateLocalHealthStore _store;
  final LifeMateLocalNamespace _namespace;
  final bool _ownsStore;
  bool _closed = false;

  static Future<WomenDailyLogOfflineCache> openDefault({
    required LifeMateLocalNamespace namespace,
  }) async {
    final store = await LifeMateLocalHealthStore.openDefault();
    return WomenDailyLogOfflineCache._owned(
      store: store,
      namespace: namespace,
    );
  }

  /// Replaces the canonical cache for exactly one fully fetched server day.
  /// The coverage marker is deleted first and written last. A process death
  /// therefore degrades to "not cached" rather than exposing a partial/stale
  /// day as canonical truth.
  Future<void> cacheServerDay({
    required DateTime date,
    required Iterable<Map<String, dynamic>> serverRows,
  }) async {
    _requireOpen();
    final day = _dateOnly(date);
    final dayText = _dateText(day);
    final rows = serverRows
        .map((value) => Map<String, dynamic>.from(value))
        .toList(growable: false);
    if (rows.length > 1) {
      throw const FormatException(
        'A Women Health daily-log day cannot contain multiple canonical rows.',
      );
    }

    final rowKey = '$_rowPrefix$dayText';
    final coverageKey = '$_coveragePrefix$dayText';
    Map<String, dynamic>? normalizedRow;
    if (rows.isNotEmpty) {
      normalizedRow = _normalizeServerRow(rows.single, expectedDay: day);
    }

    await _store.deleteProjection(
      namespace: _namespace,
      domain: LifeMateLocalProjectionDomain.syncMetadata,
      recordKey: coverageKey,
    );

    if (normalizedRow == null) {
      await _store.deleteProjection(
        namespace: _namespace,
        domain: LifeMateLocalProjectionDomain.womenHealthCycle,
        recordKey: rowKey,
      );
    } else {
      await _store.putProjection(
        namespace: _namespace,
        domain: LifeMateLocalProjectionDomain.womenHealthCycle,
        recordKey: rowKey,
        payload: normalizedRow,
        sourceRevision: normalizedRow['version'].toString(),
      );
    }

    await _store.putProjection(
      namespace: _namespace,
      domain: LifeMateLocalProjectionDomain.syncMetadata,
      recordKey: coverageKey,
      payload: <String, dynamic>{
        'version': _coverageVersion,
        'loggedOn': dayText,
        'hasRow': normalizedRow != null,
      },
    );
  }

  /// Caches a bounded, fully fetched canonical date window without inventing
  /// missing days. Each day is independently committed using [cacheServerDay].
  /// If the process dies midway, [readServerRange] returns null until every day
  /// in the requested range has a valid coverage marker.
  Future<void> cacheServerRange({
    required DateTime fromDate,
    required DateTime toDate,
    required Iterable<Map<String, dynamic>> serverRows,
  }) async {
    _requireOpen();
    final range = _validatedRange(fromDate, toDate);
    final rowsByDay = <String, List<Map<String, dynamic>>>{};
    for (final raw in serverRows) {
      final loggedOn = DateTime.tryParse(raw['loggedOn']?.toString() ?? '');
      if (loggedOn == null) {
        throw const FormatException(
          'Women Health daily-log cache row has an invalid date.',
        );
      }
      final day = _dateOnly(loggedOn);
      if (day.isBefore(range.$1) || day.isAfter(range.$2)) {
        throw const FormatException(
          'Women Health daily-log cache row is outside the confirmed range.',
        );
      }
      final key = _dateText(day);
      final bucket = rowsByDay.putIfAbsent(
        key,
        () => <Map<String, dynamic>>[],
      );
      bucket.add(Map<String, dynamic>.from(raw));
      if (bucket.length > 1) {
        throw const FormatException(
          'A Women Health daily-log day cannot contain multiple canonical rows.',
        );
      }
    }

    for (var day = range.$1;
        !day.isAfter(range.$2);
        day = day.add(const Duration(days: 1))) {
      await cacheServerDay(
        date: day,
        serverRows: rowsByDay[_dateText(day)] ?? const <Map<String, dynamic>>[],
      );
    }
  }

  /// Returns null unless every day in this bounded window was previously
  /// server-confirmed locally. Confirmed-empty days are retained as coverage
  /// but omitted from the returned row list.
  Future<List<Map<String, dynamic>>?> readServerRange({
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    _requireOpen();
    final range = _validatedRange(fromDate, toDate);
    final rows = <Map<String, dynamic>>[];
    for (var day = range.$1;
        !day.isAfter(range.$2);
        day = day.add(const Duration(days: 1))) {
      final cached = await readServerDay(day);
      if (cached == null) return null;
      rows.addAll(cached);
    }
    return List<Map<String, dynamic>>.unmodifiable(rows);
  }

  /// Returns null when this exact day has never been confirmed locally, an
  /// empty list when the server previously confirmed the day had no entry, or
  /// one canonical row when it was cached successfully.
  Future<List<Map<String, dynamic>>?> readServerDay(DateTime date) async {
    _requireOpen();
    final day = _dateOnly(date);
    final dayText = _dateText(day);
    final coverageKey = '$_coveragePrefix$dayText';
    final coverage = await _store.readProjection(
      namespace: _namespace,
      domain: LifeMateLocalProjectionDomain.syncMetadata,
      recordKey: coverageKey,
    );
    if (coverage == null) return null;

    final payload = coverage.payload;
    if (payload['version'] != _coverageVersion ||
        payload['loggedOn']?.toString() != dayText ||
        payload['hasRow'] is! bool) {
      throw const FormatException(
        'Invalid Women Health daily-log cache coverage marker.',
      );
    }
    if (payload['hasRow'] == false) {
      return const <Map<String, dynamic>>[];
    }

    final row = await _store.readProjection(
      namespace: _namespace,
      domain: LifeMateLocalProjectionDomain.womenHealthCycle,
      recordKey: '$_rowPrefix$dayText',
    );
    if (row == null) {
      throw const FormatException(
        'Women Health daily-log cache coverage is incomplete.',
      );
    }
    final normalized = _normalizeServerRow(row.payload, expectedDay: day);
    return <Map<String, dynamic>>[normalized];
  }

  void close() {
    if (_closed) return;
    _closed = true;
    if (_ownsStore) _store.close();
  }

  void _requireOpen() {
    if (_closed) {
      throw StateError('Women Health daily-log offline cache is closed.');
    }
  }

  static (DateTime, DateTime) _validatedRange(
    DateTime fromDate,
    DateTime toDate,
  ) {
    final from = _dateOnly(fromDate);
    final to = _dateOnly(toDate);
    if (to.isBefore(from)) {
      throw ArgumentError.value(
        toDate,
        'toDate',
        'Women Health cache range cannot end before it starts.',
      );
    }
    final days = to.difference(from).inDays + 1;
    if (days > _maxRangeDays) {
      throw ArgumentError.value(
        days,
        'rangeDays',
        'Women Health cache range exceeds $_maxRangeDays days.',
      );
    }
    return (from, to);
  }

  static Map<String, dynamic> _normalizeServerRow(
    Map<String, dynamic> row, {
    required DateTime expectedDay,
  }) {
    final loggedOn = DateTime.tryParse(row['loggedOn']?.toString() ?? '');
    if (loggedOn == null || _dateOnly(loggedOn) != expectedDay) {
      throw const FormatException(
        'Women Health daily-log cache row has an invalid date.',
      );
    }
    final version = row['version'] is int
        ? row['version'] as int
        : int.tryParse(row['version']?.toString() ?? '');
    if (version == null || version < 0) {
      throw const FormatException(
        'Women Health daily-log cache row has an invalid version.',
      );
    }

    final moodRaw = row['mood']?.toString().trim().toLowerCase();
    if (moodRaw != null &&
        moodRaw.isNotEmpty &&
        !_allowedMoods.contains(moodRaw)) {
      throw const FormatException(
        'Women Health daily-log cache row has an invalid mood.',
      );
    }
    final energyLevel = row['energyLevel'] == null
        ? null
        : row['energyLevel'] is int
            ? row['energyLevel'] as int
            : int.tryParse(row['energyLevel'].toString());
    if (row['energyLevel'] != null &&
        (energyLevel == null || energyLevel < 1 || energyLevel > 5)) {
      throw const FormatException(
        'Women Health daily-log cache row has an invalid energy level.',
      );
    }

    final symptomsRaw = row['symptoms'];
    if (symptomsRaw != null && symptomsRaw is! List) {
      throw const FormatException(
        'Women Health daily-log cache row has invalid symptoms.',
      );
    }
    final symptoms = symptomsRaw is List
        ? symptomsRaw
              .map((value) => value.toString().trim())
              .where((value) => value.isNotEmpty)
              .toSet()
              .toList(growable: false)
        : const <String>[];
    final painLevel = row['painLevel'] == null
        ? null
        : row['painLevel'] is int
            ? row['painLevel'] as int
            : int.tryParse(row['painLevel'].toString());
    if (row['painLevel'] != null && painLevel == null) {
      throw const FormatException(
        'Women Health daily-log cache row has an invalid pain level.',
      );
    }

    return <String, dynamic>{
      'loggedOn': _dateText(expectedDay),
      'version': version,
      if (moodRaw != null && moodRaw.isNotEmpty) 'mood': moodRaw,
      if (energyLevel != null) 'energyLevel': energyLevel,
      if (row['periodFlow'] != null) 'periodFlow': row['periodFlow'].toString(),
      if (row['bloodAppearance'] != null)
        'bloodAppearance': row['bloodAppearance'].toString(),
      if (row['bloodTexture'] != null)
        'bloodTexture': row['bloodTexture'].toString(),
      if (painLevel != null) 'painLevel': painLevel,
      'symptoms': symptoms,
      if (row['privateNotes'] != null)
        'privateNotes': row['privateNotes'].toString(),
    };
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);

  static String _dateText(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
