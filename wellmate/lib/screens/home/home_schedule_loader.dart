import 'package:lifemate_client/lifemate_client.dart';

class HomeScheduleSnapshot {
  const HomeScheduleSnapshot({
    required this.currentUser,
    required this.treatmentPlans,
    required this.doseOccurrences,
    required this.careEvents,
    required this.failures,
  });

  final Map<String, dynamic> currentUser;
  final List<Map<String, dynamic>> treatmentPlans;
  final List<Map<String, dynamic>> doseOccurrences;
  final List<Map<String, dynamic>> careEvents;
  final List<HomeScheduleLoadFailure> failures;

  bool get isPartial => failures.isNotEmpty;
}

class HomeScheduleLoadFailure {
  const HomeScheduleLoadFailure({
    required this.source,
    required this.error,
  });

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
    // Start all requests before awaiting them so the home screen remains fast.
    final currentUserFuture = _capture(
      'current-user',
      api.getCurrentUser(),
    );
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

    // Identity is required. Do not turn an authentication/session problem into
    // a misleading empty dashboard.
    currentUser.throwIfFailed();

    // A deployment mismatch in one optional schedule endpoint must not hide
    // data returned successfully by the other endpoint. Only fail the whole
    // dashboard when neither medicines nor care events can be loaded.
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
  const _HomeLoadResult.success(this.value)
    : failure = null,
      stackTrace = null;

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
