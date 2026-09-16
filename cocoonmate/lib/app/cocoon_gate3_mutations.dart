import 'package:lifemate_client/lifemate_client.dart';

enum CocoonGate3MutationDisposition { confirmed, queued }

class CocoonGate3MutationResult {
  const CocoonGate3MutationResult({
    required this.clientRequestId,
    required this.disposition,
  });

  final String clientRequestId;
  final CocoonGate3MutationDisposition disposition;
}

typedef CocoonGate3RequestIdFactory = String Function();
typedef CocoonGate3Clock = DateTime Function();
typedef CocoonGate3Close = void Function();
typedef CocoonGate3CheckInOnlineSubmit =
    Future<void> Function({
      required String clientRequestId,
      required DateTime observedAtUtc,
      required String localDate,
      required String timeZone,
      required CocoonPregnancyFeeling feeling,
      required CocoonPregnancyEnergy energy,
    });
typedef CocoonGate3CheckInOfflineEnqueue =
    Future<void> Function({
      required String clientRequestId,
      required DateTime observedAtUtc,
      required DateTime localDate,
      required String feeling,
      required String energy,
    });
typedef CocoonGate3MeasurementOnlineSubmit =
    Future<void> Function({
      required String clientRequestId,
      required CocoonPregnancyMeasurementType type,
      required double valuePrimary,
      double? valueSecondary,
      String? note,
      required DateTime observedAtUtc,
      required DateTime observedLocalDate,
      required String timeZone,
    });
typedef CocoonGate3MeasurementOfflineEnqueue =
    Future<void> Function({
      required String clientRequestId,
      required String observationType,
      required double valuePrimary,
      double? valueSecondary,
      String? note,
      required DateTime observedAtUtc,
      required DateTime observedLocalDate,
    });
typedef CocoonGate3MoodOnlineSubmit =
    Future<void> Function({
      required String clientRequestId,
      required DateTime observedAtUtc,
      required String localDate,
      required String timeZone,
      required CocoonPregnancyMood mood,
    });
typedef CocoonGate3MoodOfflineEnqueue =
    Future<void> Function({
      required String clientRequestId,
      required DateTime observedAtUtc,
      required DateTime localDate,
      required String moodCode,
    });

/// Gate-3 mutation bridge for canonical pregnancy captures.
///
/// The online API and durable outbox receive the same stable request UUID. A
/// queued result is local-only and MUST NOT be presented as server-confirmed;
/// callers refresh authoritative read models after replay/online success.
final class CocoonGate3MutationAdapter {
  CocoonGate3MutationAdapter({
    required this.timeZone,
    required CocoonGate3CheckInOnlineSubmit submitCheckInOnline,
    required CocoonGate3CheckInOfflineEnqueue enqueueCheckInOffline,
    required CocoonGate3MeasurementOnlineSubmit submitMeasurementOnline,
    required CocoonGate3MeasurementOfflineEnqueue enqueueMeasurementOffline,
    CocoonGate3MoodOnlineSubmit? submitMoodOnline,
    CocoonGate3MoodOfflineEnqueue? enqueueMoodOffline,
    CocoonGate3RequestIdFactory? requestIdFactory,
    CocoonGate3Clock? clock,
    CocoonGate3Close? close,
  }) : _submitCheckInOnline = submitCheckInOnline,
       _enqueueCheckInOffline = enqueueCheckInOffline,
       _submitMeasurementOnline = submitMeasurementOnline,
       _enqueueMeasurementOffline = enqueueMeasurementOffline,
       _submitMoodOnline = submitMoodOnline,
       _enqueueMoodOffline = enqueueMoodOffline,
       _requestIdFactory =
           requestIdFactory ?? LifeMateApiClient.createClientRequestId,
       _clock = clock ?? DateTime.now,
       _close = close {
    if (timeZone.trim().isEmpty) {
      throw ArgumentError.value(timeZone, 'timeZone', 'must not be empty.');
    }
    if ((submitMoodOnline == null) != (enqueueMoodOffline == null)) {
      throw ArgumentError(
        'Mood online and offline mutation handlers must be configured together.',
      );
    }
  }

  factory CocoonGate3MutationAdapter.production({
    required Uri baseUri,
    required AccessTokenProvider accessToken,
    required CocoonPregnancyOfflineOwnerCoordinator offlineOwner,
    String timeZone = 'Asia/Tehran',
  }) {
    final daily = CocoonPregnancyDailyApiClient(
      baseUri: baseUri,
      accessToken: accessToken,
    );
    final measurements = CocoonPregnancyMeasurementsApiClient(
      baseUri: baseUri,
      accessToken: accessToken,
    );
    return CocoonGate3MutationAdapter(
      timeZone: timeZone,
      submitCheckInOnline:
          ({
            required clientRequestId,
            required observedAtUtc,
            required localDate,
            required timeZone,
            required feeling,
            required energy,
          }) async {
            await daily.createCheckIn(
              clientRequestId: clientRequestId,
              observedAtUtc: observedAtUtc,
              localDate: localDate,
              timeZone: timeZone,
              feeling: feeling,
              energy: energy,
            );
          },
      enqueueCheckInOffline:
          ({
            required clientRequestId,
            required observedAtUtc,
            required localDate,
            required feeling,
            required energy,
          }) => offlineOwner.enqueueDailyCheckIn(
            clientRequestId: clientRequestId,
            observedAtUtc: observedAtUtc,
            localDate: localDate,
            feeling: feeling,
            energy: energy,
          ),
      submitMeasurementOnline:
          ({
            required clientRequestId,
            required type,
            required valuePrimary,
            valueSecondary,
            note,
            required observedAtUtc,
            required observedLocalDate,
            required timeZone,
          }) async {
            await measurements.create(
              clientRequestId: clientRequestId,
              type: type,
              valuePrimary: valuePrimary,
              valueSecondary: valueSecondary,
              note: note,
              observedAtUtc: observedAtUtc,
              observedLocalDate: observedLocalDate,
              timeZone: timeZone,
            );
          },
      enqueueMeasurementOffline:
          ({
            required clientRequestId,
            required observationType,
            required valuePrimary,
            valueSecondary,
            note,
            required observedAtUtc,
            required observedLocalDate,
          }) => offlineOwner.enqueueMeasurement(
            clientRequestId: clientRequestId,
            observationType: observationType,
            valuePrimary: valuePrimary,
            valueSecondary: valueSecondary,
            note: note,
            observedAtUtc: observedAtUtc,
            observedLocalDate: observedLocalDate,
          ),
      submitMoodOnline:
          ({
            required clientRequestId,
            required observedAtUtc,
            required localDate,
            required timeZone,
            required mood,
          }) async {
            await daily.createMood(
              clientRequestId: clientRequestId,
              observedAtUtc: observedAtUtc,
              localDate: localDate,
              timeZone: timeZone,
              mood: mood,
            );
          },
      enqueueMoodOffline:
          ({
            required clientRequestId,
            required observedAtUtc,
            required localDate,
            required moodCode,
          }) => offlineOwner.enqueueMood(
            clientRequestId: clientRequestId,
            observedAtUtc: observedAtUtc,
            localDate: localDate,
            moodCode: moodCode,
          ),
      close: () {
        daily.close();
        measurements.close();
      },
    );
  }

  final String timeZone;
  final CocoonGate3CheckInOnlineSubmit _submitCheckInOnline;
  final CocoonGate3CheckInOfflineEnqueue _enqueueCheckInOffline;
  final CocoonGate3MeasurementOnlineSubmit _submitMeasurementOnline;
  final CocoonGate3MeasurementOfflineEnqueue _enqueueMeasurementOffline;
  final CocoonGate3MoodOnlineSubmit? _submitMoodOnline;
  final CocoonGate3MoodOfflineEnqueue? _enqueueMoodOffline;
  final CocoonGate3RequestIdFactory _requestIdFactory;
  final CocoonGate3Clock _clock;
  final CocoonGate3Close? _close;

  Future<CocoonGate3MutationResult> submitCheckIn({
    required CocoonPregnancyFeeling feeling,
    required CocoonPregnancyEnergy energy,
  }) async {
    final requestId = _newRequestId();
    final observedLocal = _clock();
    final observedAtUtc = observedLocal.toUtc();
    final localDate = DateTime(
      observedLocal.year,
      observedLocal.month,
      observedLocal.day,
    );
    try {
      await _submitCheckInOnline(
        clientRequestId: requestId,
        observedAtUtc: observedAtUtc,
        localDate: _date(localDate),
        timeZone: timeZone,
        feeling: feeling,
        energy: energy,
      );
      return CocoonGate3MutationResult(
        clientRequestId: requestId,
        disposition: CocoonGate3MutationDisposition.confirmed,
      );
    } on LifeMateApiException catch (error) {
      if (error.statusCode != 0) rethrow;
      await _enqueueCheckInOffline(
        clientRequestId: requestId,
        observedAtUtc: observedAtUtc,
        localDate: localDate,
        feeling: feeling.wireValue,
        energy: energy.wireValue,
      );
      return CocoonGate3MutationResult(
        clientRequestId: requestId,
        disposition: CocoonGate3MutationDisposition.queued,
      );
    }
  }

  Future<CocoonGate3MutationResult> submitMeasurement({
    required CocoonPregnancyMeasurementType type,
    required double valuePrimary,
    double? valueSecondary,
    String? note,
  }) async {
    final requestId = _newRequestId();
    final observedLocal = _clock();
    final observedAtUtc = observedLocal.toUtc();
    final localDate = DateTime(
      observedLocal.year,
      observedLocal.month,
      observedLocal.day,
    );
    try {
      await _submitMeasurementOnline(
        clientRequestId: requestId,
        type: type,
        valuePrimary: valuePrimary,
        valueSecondary: valueSecondary,
        note: note,
        observedAtUtc: observedAtUtc,
        observedLocalDate: localDate,
        timeZone: timeZone,
      );
      return CocoonGate3MutationResult(
        clientRequestId: requestId,
        disposition: CocoonGate3MutationDisposition.confirmed,
      );
    } on LifeMateApiException catch (error) {
      if (error.statusCode != 0) rethrow;
      await _enqueueMeasurementOffline(
        clientRequestId: requestId,
        observationType: type.wireValue,
        valuePrimary: valuePrimary,
        valueSecondary: valueSecondary,
        note: note,
        observedAtUtc: observedAtUtc,
        observedLocalDate: localDate,
      );
      return CocoonGate3MutationResult(
        clientRequestId: requestId,
        disposition: CocoonGate3MutationDisposition.queued,
      );
    }
  }

  Future<CocoonGate3MutationResult> submitMood({
    required CocoonPregnancyMood mood,
  }) async {
    final online = _submitMoodOnline;
    final offline = _enqueueMoodOffline;
    if (online == null || offline == null) {
      throw StateError('Mood mutation is not configured.');
    }

    final requestId = _newRequestId();
    final observedLocal = _clock();
    final observedAtUtc = observedLocal.toUtc();
    final localDate = DateTime(
      observedLocal.year,
      observedLocal.month,
      observedLocal.day,
    );
    try {
      await online(
        clientRequestId: requestId,
        observedAtUtc: observedAtUtc,
        localDate: _date(localDate),
        timeZone: timeZone,
        mood: mood,
      );
      return CocoonGate3MutationResult(
        clientRequestId: requestId,
        disposition: CocoonGate3MutationDisposition.confirmed,
      );
    } on LifeMateApiException catch (error) {
      if (error.statusCode != 0) rethrow;
      await offline(
        clientRequestId: requestId,
        observedAtUtc: observedAtUtc,
        localDate: localDate,
        moodCode: mood.wireValue,
      );
      return CocoonGate3MutationResult(
        clientRequestId: requestId,
        disposition: CocoonGate3MutationDisposition.queued,
      );
    }
  }

  void close() => _close?.call();

  String _newRequestId() {
    final value = _requestIdFactory().trim();
    if (value.isEmpty) {
      throw StateError('Mutation request id factory returned an empty value.');
    }
    return value;
  }

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
