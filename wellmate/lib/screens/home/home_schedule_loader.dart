import 'package:flutter/foundation.dart';
import 'package:lifemate_client/lifemate_client.dart';

@immutable
class HomeOfflinePresentationState {
  const HomeOfflinePresentationState({
    this.cached = false,
    this.cachedAtUtc,
  });

  final bool cached;
  final DateTime? cachedAtUtc;
}

final ValueNotifier<HomeOfflinePresentationState> homeOfflinePresentationState =
    ValueNotifier<HomeOfflinePresentationState>(
      const HomeOfflinePresentationState(),
    );

class HomeScheduleSnapshot {
  const HomeScheduleSnapshot({
    required this.currentUser,
    required this.treatmentPlans,
    required this.doseOccurrences,
    required this.careEvents,
    required this.failures,
    this.offlineCached = false,
    this.offlineCachedAtUtc,
  });

  final Map<String, dynamic> currentUser;
  final List<Map<String, dynamic>> treatmentPlans;
  final List<Map<String, dynamic>> doseOccurrences;
  final List<Map<String, dynamic>> careEvents;
  final List<HomeScheduleLoadFailure> failures;
  final bool offlineCached;
  final DateTime? offlineCachedAtUtc;

  bool get isPartial => failures.isNotEmpty;
}

class HomeScheduleLoadFailure {
  const HomeScheduleLoadFailure({required this.source, required this.error});

  final String source;
  final Object error;
}

class HomeScheduleLoadException implements Exception {
  const HomeScheduleLoadException(this.failures);

  final List<HomeScheduleLoadFailure> failures;

  @override
  String toString() =>
      'HomeScheduleLoadException(${failures.map((value) => value.source).join(', ')})';
}

class HomeScheduleLoader {
  const HomeScheduleLoader();

  Future<HomeScheduleSnapshot> load({
    required LifeMateApiClient api,
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    try {
      final value = await api.getHomeSnapshot(
        fromDate: fromDate,
        toDate: toDate,
      );
      final offlineCached = value['offlineCached'] == true;
      final cachedAt = DateTime.tryParse(
        value['offlineCachedAtUtc']?.toString() ?? '',
      )?.toUtc();
      homeOfflinePresentationState.value = HomeOfflinePresentationState(
        cached: offlineCached,
        cachedAtUtc: offlineCached ? cachedAt : null,
      );
      return HomeScheduleSnapshot(
        currentUser: _object(value['currentUser'], 'currentUser'),
        treatmentPlans: _objects(value['treatmentPlans'], 'treatmentPlans'),
        doseOccurrences: _objects(value['doseOccurrences'], 'doseOccurrences'),
        careEvents: _objects(value['careEvents'], 'careEvents'),
        failures: const [],
        offlineCached: offlineCached,
        offlineCachedAtUtc: offlineCached ? cachedAt : null,
      );
    } on LifeMateApiException catch (error) {
      if (error.statusCode != 404 || error.code != 'route_not_found') {
        homeOfflinePresentationState.value =
            const HomeOfflinePresentationState();
        rethrow;
      }
      homeOfflinePresentationState.value = const HomeOfflinePresentationState();
      return _loadLegacy(api: api, fromDate: fromDate, toDate: toDate);
    } catch (_) {
      homeOfflinePresentationState.value = const HomeOfflinePresentationState();
      rethrow;
    }
  }

  Future<HomeScheduleSnapshot> _loadLegacy({
    required LifeMateApiClient api,
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    final currentUserFuture = _capture('current-user', api.getCurrentUser());
    final treatmentPlansFuture = _capture(
      'treatment-plans',
      api.getTreatmentPlans(),
    );
    final doseOccurrencesFuture = _capture(
      'dose-occurrences',
      api.getDoseOccurrences(fromDate: fromDate, toDate: toDate),
    );
    final careEventsFuture = _capture(
      'care-events',
      api.getCareEvents(fromDate: fromDate, toDate: toDate),
    );

    final currentUser = await currentUserFuture;
    final treatmentPlans = await treatmentPlansFuture;
    final doseOccurrences = await doseOccurrencesFuture;
    final careEvents = await careEventsFuture;
    currentUser.throwIfFailed();
    if (doseOccurrences.hasFailed && careEvents.hasFailed) {
      throw HomeScheduleLoadException([
        doseOccurrences.failure!,
        careEvents.failure!,
      ]);
    }
    final failures = <HomeScheduleLoadFailure>[
      if (treatmentPlans.failure case final failure?) failure,
      if (doseOccurrences.failure case final failure?) failure,
      if (careEvents.failure case final failure?) failure,
    ];
    return HomeScheduleSnapshot(
      currentUser: currentUser.value!,
      treatmentPlans: treatmentPlans.value ?? const [],
      doseOccurrences: doseOccurrences.value ?? const [],
      careEvents: careEvents.value ?? const [],
      failures: List<HomeScheduleLoadFailure>.unmodifiable(failures),
    );
  }

  Map<String, dynamic> _object(dynamic value, String field) {
    if (value is Map<String, dynamic>) return value;
    throw FormatException('Home snapshot field $field is not an object.');
  }

  List<Map<String, dynamic>> _objects(dynamic value, String field) {
    if (value is! List) {
      throw FormatException('Home snapshot field $field is not a list.');
    }
    return value.map((item) => _object(item, field)).toList(growable: false);
  }

  Future<_HomeLoadResult<T>> _capture<T>(
    String source,
    Future<T> request,
  ) async {
    try {
      return _HomeLoadResult<T>.success(await request);
    } catch (error, stackTrace) {
      return _HomeLoadResult<T>.failure(
        HomeScheduleLoadFailure(source: source, error: error),
        stackTrace,
      );
    }
  }
}

class _HomeLoadResult<T> {
  const _HomeLoadResult.success(this.value) : failure = null, stackTrace = null;

  const _HomeLoadResult.failure(this.failure, this.stackTrace) : value = null;

  final T? value;
  final HomeScheduleLoadFailure? failure;
  final StackTrace? stackTrace;

  bool get hasFailed => failure != null;

  void throwIfFailed() {
    final failed = failure;
    if (failed == null) return;
    Error.throwWithStackTrace(failed.error, stackTrace ?? StackTrace.current);
  }
}
