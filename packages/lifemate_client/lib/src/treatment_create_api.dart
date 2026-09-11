import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config.dart';
import 'lifemate_api_client.dart';
import 'recurrence.dart';
import 'reminder_lead_time.dart';

/// Focused client for the atomic medication + treatment-plan create contract.
///
/// This deliberately sends one idempotent HTTP mutation so a downstream plan
/// failure can never leave a medication row behind. It is separate from the
/// legacy `createMedication` + `createTreatmentPlan` methods while older
/// callers migrate to the composite server contract.
class LifeMateTreatmentCreateApi {
  LifeMateTreatmentCreateApi({
    required Uri baseUri,
    required AccessTokenProvider accessToken,
    http.Client? httpClient,
  }) : _baseUri = baseUri,
       _accessToken = accessToken,
       _http = httpClient ?? http.Client();

  factory LifeMateTreatmentCreateApi.fromEnvironment() {
    final config = AppConfig.fromEnvironment();
    return LifeMateTreatmentCreateApi(
      baseUri: config.apiBaseUri,
      accessToken: () => Supabase.instance.client.auth.currentSession?.accessToken,
    );
  }

  final Uri _baseUri;
  final AccessTokenProvider _accessToken;
  final http.Client _http;

  static const _requestTimeout = Duration(seconds: 20);
  static const _retryBudget = Duration(seconds: 30);
  static const _retryBaseDelay = Duration(milliseconds: 250);
  static const _retryMaxDelay = Duration(seconds: 2);
  static const _transientStatusCodes = <int>{502, 503, 504};
  static final Random _retryRandom = Random.secure();

  Future<Map<String, dynamic>> createTreatment({
    required String clientRequestId,
    required String medicationName,
    String? strengthText,
    String? form,
    String? medicationNotes,
    required String doseText,
    String? instructions,
    required DateTime startDate,
    DateTime? endDate,
    required String timeZone,
    required List<Map<String, String>> schedules,
    RecurrenceRule recurrence = const RecurrenceRule.none(),
    String? recurrenceStartLocalTime,
    int patientReminderMinutesBefore =
        LifeMateReminderLeadTimes.defaultPatientMinutes,
    int caregiverReminderMinutesBefore =
        LifeMateReminderLeadTimes.defaultCaregiverMinutes,
  }) async {
    final requestId = clientRequestId.trim();
    if (requestId.isEmpty) {
      throw ArgumentError.value(
        clientRequestId,
        'clientRequestId',
        'Atomic treatment creation requires a stable client request id.',
      );
    }
    if (recurrence.enabled &&
        (recurrenceStartLocalTime == null ||
            recurrenceStartLocalTime.trim().isEmpty)) {
      throw ArgumentError.value(
        recurrenceStartLocalTime,
        'recurrenceStartLocalTime',
        'Recurring treatment plans require a local anchor time.',
      );
    }

    final token = _accessToken();
    if (token == null || token.isEmpty) {
      throw const LifeMateApiException(
        statusCode: 401,
        code: 'session_missing',
        message: 'Authentication session is missing.',
      );
    }

    final uri = _resolve('/api/v1/treatment-plans');
    final encodedBody = jsonEncode(<String, dynamic>{
      'clientRequestId': requestId,
      'medication': <String, dynamic>{
        'name': medicationName.trim(),
        'strengthText': _emptyToNull(strengthText),
        'form': _emptyToNull(form),
        'notes': _emptyToNull(medicationNotes),
      },
      'doseText': doseText.trim(),
      'instructions': _emptyToNull(instructions),
      'startDate': _date(startDate),
      'endDate': endDate == null ? null : _date(endDate),
      'timeZone': timeZone.trim(),
      'schedules': recurrence.enabled ? const <Map<String, String>>[] : schedules,
      'recurrence': recurrence.toJson(),
      'recurrenceStartLocalTime': recurrence.enabled
          ? recurrenceStartLocalTime!.trim()
          : null,
      'patientReminderMinutesBefore': patientReminderMinutesBefore,
      'caregiverReminderMinutesBefore': caregiverReminderMinutesBefore,
    });
    final headers = <String, String>{
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      'Idempotency-Key': requestId,
    };

    final budget = Stopwatch()..start();
    for (var attempt = 1; attempt <= 3; attempt += 1) {
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
        milliseconds: min(
          _requestTimeout.inMilliseconds,
          remainingMilliseconds,
        ),
      );

      late final http.Response response;
      try {
        response = await _http
            .post(uri, headers: headers, body: encodedBody)
            .timeout(attemptTimeout);
      } on TimeoutException {
        if (attempt < 3 && await _waitBeforeRetry(attempt, budget)) continue;
        throw const LifeMateApiException(
          statusCode: 0,
          code: 'network_timeout',
          message: 'LifeMate request timed out.',
        );
      } on http.ClientException {
        if (attempt < 3 && await _waitBeforeRetry(attempt, budget)) continue;
        throw const LifeMateApiException(
          statusCode: 0,
          code: 'network_unavailable',
          message: 'LifeMate service is unavailable.',
        );
      }

      final retryResponse = _shouldRetryResponse(response);
      if (attempt < 3 &&
          retryResponse &&
          await _waitBeforeRetry(attempt, budget, response: response)) {
        continue;
      }
      return _decodeResponse(response);
    }

    throw StateError('LifeMate atomic treatment retry loop exited unexpectedly.');
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
    final exponent = 1 << (attempt - 1);
    final exponential = _retryBaseDelay.inMilliseconds * exponent;
    final jitter = _retryRandom.nextInt(_retryBaseDelay.inMilliseconds + 1);
    return Duration(
      milliseconds: min(_retryMaxDelay.inMilliseconds, exponential + jitter),
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

  Map<String, dynamic> _decodeResponse(http.Response response) {
    dynamic decoded;
    if (response.body.isNotEmpty) {
      try {
        decoded = jsonDecode(response.body);
      } on FormatException {
        if (response.statusCode >= 200 && response.statusCode < 300) {
          throw const FormatException(
            'LifeMate API returned an invalid JSON payload.',
          );
        }
      }
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (decoded is Map<String, dynamic>) return decoded;
      throw const FormatException('LifeMate API returned a non-object payload.');
    }

    final problem = decoded is Map<String, dynamic> ? decoded : const {};
    final correlationId = problem['correlationId']?.toString();
    developer.log(
      'atomic_treatment_create_failed status=${response.statusCode} '
      'code=${problem['code'] ?? problem['title'] ?? 'request_failed'} '
      'correlation=${correlationId ?? 'none'}',
      name: 'LifeMateTreatmentCreateApi',
      level: 1000,
    );
    throw LifeMateApiException(
      statusCode: response.statusCode,
      code: (problem['code'] ?? problem['title'] ?? 'request_failed')
          .toString(),
      message: (problem['detail'] ?? 'LifeMate request failed.').toString(),
      correlationId: correlationId,
    );
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

  void close() => _http.close();
}
