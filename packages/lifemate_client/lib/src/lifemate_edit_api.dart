import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config.dart';
import 'lifemate_api_client.dart';

typedef LifeMateEditAccessTokenProvider = String? Function();

class LifeMateEditApi {
  LifeMateEditApi({
    required Uri baseUri,
    required LifeMateEditAccessTokenProvider accessToken,
    http.Client? httpClient,
  }) : _baseUri = baseUri,
       _accessToken = accessToken,
       _http = httpClient ?? http.Client();

  factory LifeMateEditApi.fromEnvironment({http.Client? httpClient}) {
    final config = AppConfig.fromEnvironment();
    return LifeMateEditApi(
      baseUri: config.apiBaseUri,
      accessToken: () =>
          Supabase.instance.client.auth.currentSession?.accessToken,
      httpClient: httpClient,
    );
  }

  final Uri _baseUri;
  final LifeMateEditAccessTokenProvider _accessToken;
  final http.Client _http;

  static const _timeout = Duration(seconds: 20);
  static const _retryBudget = Duration(seconds: 30);
  static const _retryBaseDelay = Duration(milliseconds: 250);
  static const _retryMaxDelay = Duration(seconds: 2);
  static const _transientStatusCodes = <int>{502, 503, 504};
  static final Random _retryRandom = Random.secure();

  Future<Map<String, dynamic>> getCareEvent({required String eventId}) async =>
      _object(
        await _request(
          'GET',
          '/api/v1/care-events/$eventId',
          retryable: true,
        ),
      );

  Future<Map<String, dynamic>> updateCareEventStatus({
    required String eventId,
    required String status,
    int? expectedVersion,
  }) async {
    final event = await getCareEvent(eventId: eventId);
    final currentVersion = int.tryParse(event['version']?.toString() ?? '') ?? 1;
    if (expectedVersion != null && currentVersion != expectedVersion) {
      throw const LifeMateApiException(
        statusCode: 409,
        code: 'stale_care_event',
        message: 'The care event changed before this action could be applied.',
      );
    }
    final eventType =
        event['eventType']?.toString().trim().toLowerCase() == 'injection'
        ? 'injection'
        : 'appointment';
    final title = event['title']?.toString().trim() ?? '';
    final scheduledLocalDate = DateTime.tryParse(
      event['scheduledLocalDate']?.toString() ?? '',
    );
    if (scheduledLocalDate == null) {
      throw const FormatException('Care event is missing scheduledLocalDate.');
    }

    return updateCareEvent(
      eventId: eventId,
      version: currentVersion,
      eventType: eventType,
      title: title,
      providerName: _emptyToNull(event['providerName']?.toString()),
      specialty: _emptyToNull(event['specialty']?.toString()),
      medicationName: eventType == 'injection'
          ? (_emptyToNull(event['medicationName']?.toString()) ?? title)
          : null,
      doseText: _emptyToNull(event['doseText']?.toString()),
      administrationRoute: _emptyToNull(
        event['administrationRoute']?.toString(),
      ),
      reason: _emptyToNull(event['reason']?.toString()),
      instructions: _emptyToNull(event['instructions']?.toString()),
      centerName: _emptyToNull(event['centerName']?.toString()),
      addressLine: _emptyToNull(event['addressLine']?.toString()),
      phoneNumber: _emptyToNull(event['phoneNumber']?.toString()),
      scheduledLocalDate: scheduledLocalDate,
      scheduledLocalTime:
          event['scheduledLocalTime']?.toString().trim() ?? '00:00',
      timeZone: event['timeZone']?.toString().trim().isNotEmpty == true
          ? event['timeZone'].toString().trim()
          : 'Asia/Tehran',
      patientReminderMinutesBefore:
          int.tryParse(
            event['patientReminderMinutesBefore']?.toString() ?? '',
          ) ??
          30,
      caregiverReminderMinutesBefore:
          int.tryParse(
            event['caregiverReminderMinutesBefore']?.toString() ?? '',
          ) ??
          60,
      status: status,
    );
  }

  Future<Map<String, dynamic>> updateTreatmentPlan({
    required String treatmentPlanId,
    required int version,
    required int medicationVersion,
    required String medicationName,
    String? strengthText,
    String? form,
    required String doseText,
    String? instructions,
    required DateTime startDate,
    DateTime? endDate,
    required String timeZone,
    required List<Map<String, String>> schedules,
    required int patientReminderMinutesBefore,
    required int caregiverReminderMinutesBefore,
    required String status,
    String? clientRequestId,
  }) async => _object(
    await _request(
      'PATCH',
      '/api/v1/treatment-plans/$treatmentPlanId',
      body: {
        'version': version,
        'medicationVersion': medicationVersion,
        'medicationName': medicationName.trim(),
        'strengthText': _emptyToNull(strengthText),
        'form': _emptyToNull(form),
        'doseText': doseText.trim(),
        'instructions': _emptyToNull(instructions),
        'startDate': _date(startDate),
        'endDate': endDate == null ? null : _date(endDate),
        'timeZone': timeZone.trim(),
        'schedules': schedules,
        'patientReminderMinutesBefore': patientReminderMinutesBefore,
        'caregiverReminderMinutesBefore': caregiverReminderMinutesBefore,
        'status': status.trim().toLowerCase(),
      },
      retryable: true,
      idempotencyKey: clientRequestId,
    ),
  );

  Future<Map<String, dynamic>> updateCareEvent({
    required String eventId,
    required int version,
    required String eventType,
    required String title,
    required DateTime scheduledLocalDate,
    required String scheduledLocalTime,
    required String timeZone,
    String? providerName,
    String? specialty,
    String? medicationName,
    String? doseText,
    String? administrationRoute,
    String? reason,
    String? instructions,
    String? centerName,
    String? addressLine,
    String? phoneNumber,
    required int patientReminderMinutesBefore,
    required int caregiverReminderMinutesBefore,
    required String status,
  }) async => _object(
    await _request(
      'PATCH',
      '/api/v1/care-events/$eventId',
      body: {
        'version': version,
        'eventType': eventType.trim().toLowerCase(),
        'title': title.trim(),
        'providerName': _emptyToNull(providerName),
        'specialty': _emptyToNull(specialty),
        'medicationName': _emptyToNull(medicationName),
        'doseText': _emptyToNull(doseText),
        'administrationRoute': _emptyToNull(administrationRoute),
        'reason': _emptyToNull(reason),
        'instructions': _emptyToNull(instructions),
        'centerName': _emptyToNull(centerName),
        'addressLine': _emptyToNull(addressLine),
        'phoneNumber': _emptyToNull(phoneNumber),
        'scheduledLocalDate': _date(scheduledLocalDate),
        'scheduledLocalTime': scheduledLocalTime.trim(),
        'timeZone': timeZone.trim(),
        'patientReminderMinutesBefore': patientReminderMinutesBefore,
        'caregiverReminderMinutesBefore': caregiverReminderMinutesBefore,
        'status': status.trim().toLowerCase(),
      },
      retryable: true,
    ),
  );

  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool retryable = false,
    String? idempotencyKey,
  }) async {
    final token = _accessToken();
    if (token == null || token.isEmpty) {
      throw const LifeMateApiException(
        statusCode: 401,
        code: 'session_missing',
        message: 'Authentication session is missing.',
      );
    }

    final uri = _baseUri.replace(
      path: '${_baseUri.path.replaceFirst(RegExp(r'/$'), '')}$path',
    );
    final isMutation = method == 'PATCH';
    final normalizedIdempotencyKey = idempotencyKey?.trim();
    final requestId = isMutation
        ? (normalizedIdempotencyKey?.isNotEmpty == true
              ? normalizedIdempotencyKey
              : LifeMateApiClient.createClientRequestId())
        : null;
    final headers = <String, String>{
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
      if (body != null) 'Content-Type': 'application/json',
      if (requestId != null) 'Idempotency-Key': requestId,
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
          message: 'LifeMate edit retry budget was exhausted.',
        );
      }
      final attemptTimeout = Duration(
        milliseconds: min(_timeout.inMilliseconds, remainingMilliseconds),
      );

      late final http.Response response;
      try {
        response = switch (method) {
          'GET' => await _http.get(uri, headers: headers).timeout(attemptTimeout),
          'PATCH' => await _http
              .patch(uri, headers: headers, body: encodedBody)
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
          message: 'The edit request timed out.',
        );
      } on http.ClientException {
        if (attempt < maxAttempts && await _waitBeforeRetry(attempt, budget)) {
          continue;
        }
        throw const LifeMateApiException(
          statusCode: 0,
          code: 'network_unavailable',
          message: 'The edit request could not reach LifeMate API.',
        );
      }

      if (
        attempt < maxAttempts &&
        _shouldRetryResponse(response) &&
        await _waitBeforeRetry(attempt, budget, response: response)
      ) {
        continue;
      }
      return _decode(response);
    }

    throw StateError('LifeMate edit retry loop exited unexpectedly.');
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
    if (
      budget.elapsedMilliseconds + delay.inMilliseconds >=
          _retryBudget.inMilliseconds
    ) {
      return false;
    }
    await Future<void>.delayed(delay);
    return true;
  }

  Duration _retryDelayForAttempt(int attempt) {
    final exponential = _retryBaseDelay.inMilliseconds * (1 << (attempt - 1));
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
      return decoded is Map &&
          decoded['code']?.toString() == 'idempotency_in_progress';
    } on FormatException {
      return false;
    }
  }

  dynamic _decode(http.Response response) {
    final decoded = response.body.trim().isEmpty
        ? null
        : jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }

    final problem = decoded is Map<String, dynamic>
        ? decoded
        : const <String, dynamic>{};
    throw LifeMateApiException(
      statusCode: response.statusCode,
      code: problem['code']?.toString() ?? 'request_failed',
      message:
          problem['detail']?.toString() ??
          problem['message']?.toString() ??
          'LifeMate edit request failed.',
    );
  }

  static Map<String, dynamic> _object(dynamic value) {
    if (value is! Map) {
      throw const FormatException(
        'LifeMate API returned a non-object payload.',
      );
    }
    return Map<String, dynamic>.from(value);
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
