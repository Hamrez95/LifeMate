import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config.dart';
import 'lifemate_api_client.dart';

class WomenCompanionApi {
  WomenCompanionApi({
    required Uri baseUri,
    required String? Function() accessToken,
    http.Client? httpClient,
  }) : _baseUri = baseUri,
       _accessToken = accessToken,
       _http = httpClient ?? http.Client();

  factory WomenCompanionApi.fromEnvironment({http.Client? httpClient}) {
    final config = AppConfig.fromEnvironment();
    return WomenCompanionApi(
      baseUri: config.apiBaseUri,
      accessToken: () =>
          Supabase.instance.client.auth.currentSession?.accessToken,
      httpClient: httpClient,
    );
  }

  final Uri _baseUri;
  final String? Function() _accessToken;
  final http.Client _http;

  static const _timeout = Duration(seconds: 20);
  static const _retryBudget = Duration(seconds: 30);
  static const _retryBaseDelay = Duration(milliseconds: 250);
  static const _retryMaxDelay = Duration(seconds: 2);
  static const _transientStatusCodes = <int>{502, 503, 504};
  static final Random _retryRandom = Random.secure();

  Future<List<Map<String, dynamic>>> getDailyLogs({
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    final value = await _send(
      'GET',
      '/api/v1/women-calendar/daily-logs',
      query: {'fromDate': _date(fromDate), 'toDate': _date(toDate)},
      retryable: true,
    );
    if (value is! List) {
      throw const FormatException('Daily logs response must be a list.');
    }
    return value
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> saveDailyLog({
    required int version,
    required DateTime loggedOn,
    required String mood,
    required int energyLevel,
    required int painLevel,
    required List<String> symptoms,
    String? privateNotes,
    required bool shareSummaryWithCompanion,
    String? clientRequestId,
  }) async {
    final value = await _send(
      'PUT',
      '/api/v1/women-calendar/daily-logs',
      body: {
        'version': version,
        'loggedOn': _date(loggedOn),
        'mood': mood.trim().toLowerCase(),
        'energyLevel': energyLevel,
        'painLevel': painLevel,
        'symptoms': symptoms
            .map((value) => value.trim().toLowerCase())
            .toList(),
        'privateNotes': _emptyToNull(privateNotes),
        'shareSummaryWithCompanion': shareSummaryWithCompanion,
      },
      idempotencyKey:
          clientRequestId ?? LifeMateApiClient.createClientRequestId(),
      retryable: true,
    );
    return Map<String, dynamic>.from(value as Map);
  }

  Future<dynamic> _send(
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
    final resolved = _resolve(path);
    final uri = query == null
        ? resolved
        : resolved.replace(queryParameters: query);
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
          'GET' =>
            await _http.get(uri, headers: headers).timeout(attemptTimeout),
          'PUT' =>
            await _http
                .put(uri, headers: headers, body: encodedBody)
                .timeout(attemptTimeout),
          _ => throw ArgumentError.value(method, 'method'),
        };
      } on TimeoutException {
        if (attempt < maxAttempts && await _waitBeforeRetry(attempt, budget)) {
          continue;
        }
        throw const LifeMateApiException(
          statusCode: 0,
          code: 'network_timeout',
          message: 'LifeMate request timed out.',
        );
      } on http.ClientException {
        if (attempt < maxAttempts && await _waitBeforeRetry(attempt, budget)) {
          continue;
        }
        throw const LifeMateApiException(
          statusCode: 0,
          code: 'network_unavailable',
          message: 'LifeMate service is unavailable.',
        );
      }

      if (attempt < maxAttempts &&
          _shouldRetryResponse(response) &&
          await _waitBeforeRetry(attempt, budget, response: response)) {
        continue;
      }
      return _decode(response);
    }

    throw StateError(
      'LifeMate women companion retry loop exited unexpectedly.',
    );
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
    final exponential = _retryBaseDelay.inMilliseconds * (1 << (attempt - 1));
    final jitter = _retryRandom.nextInt(_retryBaseDelay.inMilliseconds + 1);
    return Duration(
      milliseconds: min(_retryMaxDelay.inMilliseconds, exponential + jitter),
    );
  }

  bool _shouldRetryResponse(http.Response response) {
    if (_transientStatusCodes.contains(response.statusCode)) return true;
    if (response.statusCode != 409 || response.body.isEmpty) return false;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      return decoded is Map &&
          decoded['code']?.toString() == 'idempotency_in_progress';
    } on FormatException {
      return false;
    }
  }

  dynamic _decode(http.Response response) {
    dynamic decoded;
    if (response.body.isNotEmpty) {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final problem = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : const <String, dynamic>{};
      throw LifeMateApiException(
        statusCode: response.statusCode,
        code: problem['code']?.toString() ?? 'request_failed',
        message:
            problem['detail']?.toString() ??
            problem['message']?.toString() ??
            'The request failed.',
      );
    }
    return decoded;
  }

  Uri _resolve(String path) {
    final base = _baseUri.toString().replaceFirst(RegExp(r'/+$'), '');
    final relative = path.replaceFirst(RegExp(r'^/+'), '');
    return Uri.parse('$base/$relative');
  }

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static String? _emptyToNull(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
