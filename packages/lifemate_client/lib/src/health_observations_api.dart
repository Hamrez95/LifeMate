import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'app_config.dart';
import 'lifemate_api_client.dart';

typedef LifeMateHealthAccessTokenProvider = String? Function();

class LifeMateHealthObservation {
  const LifeMateHealthObservation({
    required this.id,
    required this.personId,
    required this.observationType,
    required this.valuePrimary,
    required this.valueSecondary,
    required this.unitPrimary,
    required this.unitSecondary,
    required this.note,
    required this.observedAtUtc,
    required this.observedLocalDate,
    required this.timeZone,
    required this.sourceCategory,
    required this.sourceProvider,
    required this.sourceApplicationCode,
    required this.version,
  });

  factory LifeMateHealthObservation.fromJson(Map<String, dynamic> json) {
    final observedAt = DateTime.tryParse(
      json['observedAtUtc']?.toString() ?? '',
    );
    final localDate = DateTime.tryParse(
      json['observedLocalDate']?.toString() ?? '',
    );
    if (observedAt == null || localDate == null) {
      throw const FormatException('Health observation contains invalid dates.');
    }
    return LifeMateHealthObservation(
      id: json['id']?.toString() ?? '',
      personId: json['personId']?.toString() ?? '',
      observationType: json['observationType']?.toString() ?? '',
      valuePrimary: _number(json['valuePrimary']),
      valueSecondary: _number(json['valueSecondary']),
      unitPrimary: json['unitPrimary']?.toString(),
      unitSecondary: json['unitSecondary']?.toString(),
      note: json['note']?.toString(),
      observedAtUtc: observedAt.toUtc(),
      observedLocalDate: DateTime(
        localDate.year,
        localDate.month,
        localDate.day,
      ),
      timeZone: json['timeZone']?.toString() ?? 'Asia/Tehran',
      sourceCategory: json['sourceCategory']?.toString() ?? '',
      sourceProvider: json['sourceProvider']?.toString() ?? '',
      sourceApplicationCode: json['sourceApplicationCode']?.toString(),
      version: int.tryParse(json['version']?.toString() ?? '') ?? 1,
    );
  }

  final String id;
  final String personId;
  final String observationType;
  final double? valuePrimary;
  final double? valueSecondary;
  final String? unitPrimary;
  final String? unitSecondary;
  final String? note;
  final DateTime observedAtUtc;
  final DateTime observedLocalDate;
  final String timeZone;
  final String sourceCategory;
  final String sourceProvider;
  final String? sourceApplicationCode;
  final int version;

  static double? _number(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }
}

class LifeMateHealthApi {
  LifeMateHealthApi({
    required Uri baseUri,
    required LifeMateHealthAccessTokenProvider accessToken,
    http.Client? httpClient,
    String applicationCode = 'wellmate',
  }) : _baseUri = baseUri,
       _accessToken = accessToken,
       _http = httpClient ?? http.Client(),
       _applicationCode = _normalizeApplicationCode(applicationCode);

  factory LifeMateHealthApi.fromEnvironment({
    http.Client? httpClient,
    String applicationCode = 'wellmate',
  }) {
    final config = AppConfig.fromEnvironment();
    return LifeMateHealthApi(
      baseUri: config.apiBaseUri,
      accessToken: () =>
          Supabase.instance.client.auth.currentSession?.accessToken,
      httpClient: httpClient,
      applicationCode: applicationCode,
    );
  }

  final Uri _baseUri;
  final LifeMateHealthAccessTokenProvider _accessToken;
  final http.Client _http;
  final String _applicationCode;
  final Map<String, String> _pendingCreateRequestIds = <String, String>{};
  static const _timeout = Duration(seconds: 20);
  static const _retryBudget = Duration(seconds: 30);
  static const _retryBaseDelay = Duration(milliseconds: 250);
  static const _retryMaxDelay = Duration(seconds: 2);
  static const _transientStatusCodes = <int>{502, 503, 504};
  static final Random _retryRandom = Random.secure();
  static bool _timeZonesInitialized = false;

  Future<List<LifeMateHealthObservation>> listObservations({
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    final value = await _request(
      'GET',
      '/api/v1/health/observations',
      query: {'fromDate': _date(fromDate), 'toDate': _date(toDate)},
      retryable: true,
    );
    if (value is! List) {
      throw const FormatException(
        'Health observations response is not a list.',
      );
    }
    return value
        .map((entry) => LifeMateHealthObservation.fromJson(_object(entry)))
        .toList(growable: false);
  }

  Future<LifeMateHealthObservation> createObservation({
    required String observationType,
    double? valuePrimary,
    double? valueSecondary,
    String? note,
    required DateTime observedAtUtc,
    required DateTime observedLocalDate,
    required String timeZone,
    String? clientRequestId,
  }) async {
    // `observedLocalDate` deliberately carries the wall-clock components from
    // the entry sheet. Convert those components using the declared profile time
    // zone rather than the device zone. This prevents travel/device-zone drift.
    final canonicalObservedAtUtc = _wallClockToUtc(observedLocalDate, timeZone);
    final fingerprint = _createFingerprint(
      observationType: observationType,
      valuePrimary: valuePrimary,
      valueSecondary: valueSecondary,
      note: note,
      observedLocalDate: observedLocalDate,
      timeZone: timeZone,
    );
    final generatedRequestId = clientRequestId == null;
    final requestId =
        clientRequestId ??
        _pendingCreateRequestIds.putIfAbsent(
          fingerprint,
          LifeMateApiClient.createClientRequestId,
        );

    try {
      final value = await _request(
        'POST',
        '/api/v1/health/observations',
        body: {
          'clientRequestId': requestId,
          'sourceApplicationCode': _applicationCode,
          'observationType': observationType.trim().toLowerCase(),
          'valuePrimary': valuePrimary,
          'valueSecondary': valueSecondary,
          'note': _emptyToNull(note),
          'observedAtUtc': canonicalObservedAtUtc.toIso8601String(),
          'observedLocalDate': _date(observedLocalDate),
          'timeZone': timeZone.trim(),
        },
        idempotencyKey: requestId,
        retryable: true,
      );
      if (generatedRequestId) {
        _pendingCreateRequestIds.remove(fingerprint);
      }
      return LifeMateHealthObservation.fromJson(_object(value));
    } catch (_) {
      // Keep the generated request ID after a timeout/network/server failure.
      // If the server committed but the response was lost, retrying the same
      // draft converges on the original observation instead of duplicating it.
      rethrow;
    }
  }

  Future<void> deleteObservation({required String observationId}) async {
    await _request(
      'DELETE',
      '/api/v1/health/observations/$observationId',
      idempotencyKey: LifeMateApiClient.createClientRequestId(),
      retryable: true,
    );
  }

  Future<dynamic> _request(
  String method,
  String path, {
  Map<String, String>? query,
  Map<String, dynamic>? body,
  String? idempotencyKey,
  bool retryable = false,
}) async {
  final token = _accessToken();
  if (token == null || token.isEmpty) {
    throw const LifeMateApiException(
      statusCode: 401,
      code: 'session_missing',
      message: 'Authentication session is missing.',
    );
  }

  var uri = _resolve(path);
  if (query != null) uri = uri.replace(queryParameters: query);
  final headers = <String, String>{
    'Accept': 'application/json',
    'Authorization': 'Bearer $token',
    if (body != null) 'Content-Type': 'application/json',
    if (idempotencyKey != null) 'Idempotency-Key': idempotencyKey,
  };
  final encodedBody = body == null ? null : jsonEncode(body);
  final maxAttempts = retryable ? 3 : 1;
  final budget = Stopwatch()..start();

  for (var attempt = 1; attempt <= maxAttempts; attempt += 1) {
    final remainingMilliseconds =
        _retryBudget.inMilliseconds - budget.elapsedMilliseconds;
    if (remainingMilliseconds <= 0) {
      throw const LifeMateApiException(
        statusCode: 0,
        code: 'retry_budget_exhausted',
        message: 'LifeMate retry budget was exhausted.',
      );
    }
    final attemptTimeout = Duration(
      milliseconds: min(_timeout.inMilliseconds, remainingMilliseconds),
    );

    late final http.Response response;
    try {
      response = switch (method) {
        'GET' => await _http.get(uri, headers: headers).timeout(attemptTimeout),
        'POST' => await _http
            .post(uri, headers: headers, body: encodedBody)
            .timeout(attemptTimeout),
        'DELETE' => await _http
            .delete(uri, headers: headers)
            .timeout(attemptTimeout),
        _ => throw ArgumentError.value(method, 'method'),
      };
    } on TimeoutException {
      if (attempt < maxAttempts &&
          await _waitBeforeRetry(attempt, budget)) {
        continue;
      }
      throw const LifeMateApiException(
        statusCode: 0,
        code: 'network_timeout',
        message: 'LifeMate request timed out.',
      );
    } on http.ClientException {
      if (attempt < maxAttempts &&
          await _waitBeforeRetry(attempt, budget)) {
        continue;
      }
      throw const LifeMateApiException(
        statusCode: 0,
        code: 'network_unavailable',
        message: 'LifeMate service is unavailable.',
      );
    }

    final retryResponse = _shouldRetryResponse(response);
    if (attempt < maxAttempts &&
        retryResponse &&
        await _waitBeforeRetry(attempt, budget, response: response)) {
      continue;
    }
    return _decodeHealthResponse(response);
  }

  throw StateError('LifeMate health retry loop exited unexpectedly.');
}

Future<bool> _waitBeforeRetry(
  int attempt,
  Stopwatch budget, {
  http.Response? response,
}) async {
  var delay = _retryDelayForAttempt(attempt);
  final retryAfter = response == null
      ? null
      : int.tryParse(response.headers['retry-after'] ?? '');
  if (retryAfter != null && retryAfter > 0) {
    final serverDelay = Duration(seconds: retryAfter);
    if (serverDelay > delay) delay = serverDelay;
  }
  if (budget.elapsedMilliseconds + delay.inMilliseconds >=
      _retryBudget.inMilliseconds) {
    return false;
  }
  await Future<void>.delayed(delay);
  return true;
}

Duration _retryDelayForAttempt(int attempt) {
  final exponential =
      _retryBaseDelay.inMilliseconds * (1 << (attempt - 1));
  final jitter = _retryRandom.nextInt(_retryBaseDelay.inMilliseconds + 1);
  return Duration(
    milliseconds: min(
      _retryMaxDelay.inMilliseconds,
      exponential + jitter,
    ),
  );
}

bool _shouldRetryResponse(http.Response response) {
  if (_transientStatusCodes.contains(response.statusCode)) return true;
  if (response.statusCode != 409 || response.body.isEmpty) return false;
  try {
    final decoded = jsonDecode(response.body);
    return decoded is Map<String, dynamic> &&
        decoded['code']?.toString() == 'idempotency_in_progress';
  } on FormatException {
    return false;
  }
}

dynamic _decodeHealthResponse(http.Response response) {
  if (response.statusCode >= 200 && response.statusCode < 300) {
    if (response.body.isEmpty) return null;
    return jsonDecode(response.body);
  }
  dynamic decoded;
  try {
    decoded = response.body.isEmpty ? null : jsonDecode(response.body);
  } on FormatException {
    decoded = null;
  }
  final problem = decoded is Map<String, dynamic> ? decoded : const {};
  throw LifeMateApiException(
    statusCode: response.statusCode,
    code: (problem['code'] ?? problem['title'] ?? 'request_failed')
        .toString(),
    message: (problem['detail'] ?? 'LifeMate request failed.').toString(),
  );
}

  DateTime _wallClockToUtc(DateTime wallClock, String timeZone) {
    if (!_timeZonesInitialized) {
      tz_data.initializeTimeZones();
      _timeZonesInitialized = true;
    }
    final normalizedZone = timeZone.trim();
    try {
      final location = tz.getLocation(normalizedZone);
      return tz.TZDateTime(
        location,
        wallClock.year,
        wallClock.month,
        wallClock.day,
        wallClock.hour,
        wallClock.minute,
        wallClock.second,
        wallClock.millisecond,
        wallClock.microsecond,
      ).toUtc();
    } catch (_) {
      // Preserve the previous safe behavior only as a compatibility fallback;
      // the server still validates the declared IANA zone and can reject it.
      return wallClock.toUtc();
    }
  }

  String _createFingerprint({
    required String observationType,
    required double? valuePrimary,
    required double? valueSecondary,
    required String? note,
    required DateTime observedLocalDate,
    required String timeZone,
  }) => jsonEncode({
    'application': _applicationCode,
    'type': observationType.trim().toLowerCase(),
    'primary': valuePrimary,
    'secondary': valueSecondary,
    'note': _emptyToNull(note),
    'wallClock':
        '${observedLocalDate.year.toString().padLeft(4, '0')}-'
        '${observedLocalDate.month.toString().padLeft(2, '0')}-'
        '${observedLocalDate.day.toString().padLeft(2, '0')}T'
        '${observedLocalDate.hour.toString().padLeft(2, '0')}:'
        '${observedLocalDate.minute.toString().padLeft(2, '0')}:'
        '${observedLocalDate.second.toString().padLeft(2, '0')}',
    'timeZone': timeZone.trim(),
  });

  Uri _resolve(String path) {
    final base = _baseUri.toString().replaceFirst(RegExp(r'/+$'), '');
    final relative = path.replaceFirst(RegExp(r'^/+'), '');
    return Uri.parse('$base/$relative');
  }

  static Map<String, dynamic> _object(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    throw const FormatException('LifeMate API returned a non-object payload.');
  }

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static String _normalizeApplicationCode(String value) {
    final normalized = value.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9][a-z0-9_-]{1,63}$').hasMatch(normalized)) {
      throw ArgumentError.value(value, 'applicationCode');
    }
    return normalized;
  }

  static String? _emptyToNull(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  void close() {
    _pendingCreateRequestIds.clear();
    _http.close();
  }
}
