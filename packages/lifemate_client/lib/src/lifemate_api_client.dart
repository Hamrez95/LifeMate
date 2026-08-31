import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'care_access_inventory.dart';
import 'care_pairing_qr.dart';
import 'lifemate_bootstrap.dart';
import 'profile_avatar.dart';

class LifeMateApiException implements Exception {
  const LifeMateApiException({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  final int statusCode;
  final String code;
  final String message;

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => 'LifeMateApiException($statusCode, $code)';
}

class LifeMateApiClient {
  LifeMateApiClient({
    required this.baseUri,
    required FutureOr<String?> Function() accessToken,
    http.Client? httpClient,
    Random? retryRandom,
  })  : _accessToken = accessToken,
        _http = httpClient ?? http.Client(),
        _retryRandom = retryRandom ?? Random.secure();

  final Uri baseUri;
  final FutureOr<String?> Function() _accessToken;
  final http.Client _http;
  final Random _retryRandom;

  static const _requestTimeout = Duration(seconds: 20);
  static const _retryBudget = Duration(seconds: 45);
  static const _retryBaseDelay = Duration(milliseconds: 250);
  static const _retryMaxDelay = Duration(seconds: 4);
  static const _transientStatusCodes = <int>{408, 425, 429, 500, 502, 503, 504};
  final Map<String, String> _pendingMutationKeys = <String, String>{};

  static String createClientRequestId() =>
      'lm-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';

  void close() => _http.close();

  Future<Map<String, dynamic>> bootstrapUser({
    String? displayName,
    String? email,
  }) async => _asObject(await _send(
        'POST',
        '/api/v1/bootstrap',
        body: {
          if (displayName != null && displayName.trim().isNotEmpty)
            'displayName': displayName.trim(),
          if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
        },
        retryable: true,
      ));

  Future<Map<String, dynamic>> getCurrentUser() async =>
      _asObject(await _send('GET', '/api/v1/me', retryable: true));

  Future<Map<String, dynamic>> getProfile() async =>
      _asObject(await _send('GET', '/api/v1/me/profile', retryable: true));

  Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> body) async =>
      _asObject(await _send('PATCH', '/api/v1/me/profile', body: body));

  Future<List<Map<String, dynamic>>> getTreatmentPlans() =>
      _getList('/api/v1/treatment-plans');

  Future<Map<String, dynamic>> getTreatmentPlan(String id) async =>
      _asObject(await _send('GET', '/api/v1/treatment-plans/$id', retryable: true));

  Future<Map<String, dynamic>> createTreatmentPlan(Map<String, dynamic> body) async =>
      _asObject(await _send('POST', '/api/v1/treatment-plans', body: body));

  Future<Map<String, dynamic>> updateTreatmentPlan(
    String id,
    Map<String, dynamic> body,
  ) async => _asObject(await _send('PATCH', '/api/v1/treatment-plans/$id', body: body));

  Future<void> deleteTreatmentPlan(String id) async {
    await _send('DELETE', '/api/v1/treatment-plans/$id');
  }

  Future<List<Map<String, dynamic>>> getDoseOccurrences({
    required DateTime fromDate,
    required DateTime toDate,
  }) => _getList(
        '/api/v1/dose-occurrences',
        query: {'fromDate': _date(fromDate), 'toDate': _date(toDate)},
      );

  Future<Map<String, dynamic>> reportDose(
    String occurrenceId,
    String status, {
    String? clientRequestId,
  }) async => _asObject(await _send(
        'POST',
        '/api/v1/dose-occurrences/$occurrenceId/report',
        body: {'status': status},
        idempotencyKey: clientRequestId,
        retryable: true,
      ));

  Future<List<Map<String, dynamic>>> getCareEvents({
    required DateTime fromDate,
    required DateTime toDate,
  }) => _getList(
        '/api/v1/care-events',
        query: {'fromDate': _date(fromDate), 'toDate': _date(toDate)},
      );

  Future<Map<String, dynamic>> createCareEvent(
    Map<String, dynamic> body, {
    String? clientRequestId,
  }) async => _asObject(await _send(
        'POST',
        '/api/v1/care-events',
        body: body,
        idempotencyKey: clientRequestId,
        retryable: true,
      ));

  Future<List<Map<String, dynamic>>> getCareRelationships() =>
      _getList('/api/v1/care/relationships');

  Future<Map<String, dynamic>> createCareInvitation({
    required String patientUserId,
    required String caregiverUserId,
    required String relationshipType,
    String? caregiverDisplayName,
  }) async => _asObject(await _send(
        'POST',
        '/api/v1/care/invitations',
        body: {
          'patientUserId': patientUserId,
          'caregiverUserId': caregiverUserId,
          'relationshipType': relationshipType,
          if (caregiverDisplayName != null) 'caregiverDisplayName': caregiverDisplayName,
        },
      ));

  Future<Map<String, dynamic>> acceptCareInvitation(String token) async =>
      _asObject(
        await _send(
          'POST',
          '/api/v1/care/invitations/accept',
          body: {
            'token': token.trim(),
            'consentVersion': 'care-caregiver-consent-v1',
            'confirmConsent': true,
          },
          retryable: true,
        ),
      );

  Future<void> revokeCareRelationship({required String relationshipId}) async {
    await _send(
      'DELETE',
      '/api/v1/care/relationships/$relationshipId',
      retryable: true,
    );
  }

  Future<List<Map<String, dynamic>>> getCareRecipientDoseOccurrences({
    required String patientUserId,
    required DateTime fromDate,
    required DateTime toDate,
  }) => _getList(
        '/api/v1/care/patients/$patientUserId/dose-occurrences',
        query: {'fromDate': _date(fromDate), 'toDate': _date(toDate)},
      );

  Future<List<Map<String, dynamic>>> getCareRecipientCareEvents({
    required String patientUserId,
    required DateTime fromDate,
    required DateTime toDate,
  }) => _getList(
        '/api/v1/care/patients/$patientUserId/care-events',
        query: {'fromDate': _date(fromDate), 'toDate': _date(toDate)},
      );

  Future<List<Map<String, dynamic>>> getWomenCompanionPrivacyScopes() =>
      _getList('/api/v1/women-calendar/companion-privacy');

  Future<Map<String, dynamic>> updateWomenCompanionPrivacyScopes({
    required String relationshipId,
    required int version,
    required Map<String, bool> scopes,
  }) async => _asObject(await _send(
        'PUT',
        '/api/v1/women-calendar/companion-privacy/$relationshipId',
        body: {'version': version, 'scopes': scopes},
      ));

  Future<Map<String, dynamic>> getWomenCalendarProfile() async => _asObject(
        await _send('GET', '/api/v1/women-calendar/profile', retryable: true),
      );

  Future<Map<String, dynamic>> getWomenCalendarDashboard({
    required DateTime fromDate,
    required DateTime toDate,
  }) async => _asObject(
        await _send(
          'GET',
          '/api/v1/women-calendar/dashboard',
          query: {'fromDate': _date(fromDate), 'toDate': _date(toDate)},
          retryable: true,
        ),
      );

  Future<Map<String, dynamic>> updateWomenCalendarProfile({
    required int version,
    required bool enabled,
    required DateTime? lastPeriodStart,
    required int cycleLength,
    required int periodLength,
    bool? cycleLengthKnown,
    bool? periodLengthKnown,
    String? regularity,
  }) async => _asObject(await _send(
        'PATCH',
        '/api/v1/women-calendar/profile',
        body: {
          'version': version,
          'enabled': enabled,
          'lastPeriodStart': lastPeriodStart == null ? null : _date(lastPeriodStart),
          'cycleLength': cycleLength,
          'periodLength': periodLength,
          if (cycleLengthKnown != null) 'cycleLengthKnown': cycleLengthKnown,
          if (periodLengthKnown != null) 'periodLengthKnown': periodLengthKnown,
          if (regularity != null) 'regularity': regularity,
        },
      ));

  Future<Map<String, dynamic>> getCareRecipientWomenCalendar({
    required String patientUserId,
  }) async => _asObject(await _send(
        'GET',
        '/api/v1/care/patients/$patientUserId/women-calendar',
        retryable: true,
      ));

  Future<Map<String, dynamic>> recordCareRecipientWomenSupportAction({
    required String patientUserId,
    required String actionType,
  }) async => _asObject(await _send(
        'POST',
        '/api/v1/care/patients/$patientUserId/women-calendar/support-actions',
        body: {'actionType': actionType},
      ));

  Future<List<Map<String, dynamic>>> _getList(
    String path, {
    Map<String, String>? query,
  }) async {
    final decoded = await _send('GET', path, query: query, retryable: true);
    if (decoded is List) {
      return decoded.whereType<Map>().map((value) => Map<String, dynamic>.from(value)).toList();
    }
    if (decoded is Map<String, dynamic>) {
      final items = decoded['items'];
      if (items is List) {
        return items.whereType<Map>().map((value) => Map<String, dynamic>.from(value)).toList();
      }
    }
    return const <Map<String, dynamic>>[];
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
    String? idempotencyKey,
    bool retryable = false,
  }) async {
    final token = await _accessToken;
    if (token == null || token.trim().isEmpty) {
      throw const LifeMateApiException(
        statusCode: 401,
        code: 'missing_session',
        message: 'Authentication is required.',
      );
    }
    var uri = baseUri.resolve(path.startsWith('/') ? path.substring(1) : path);
    if (query != null) uri = uri.replace(queryParameters: query);
    final encodedBody = body == null ? null : jsonEncode(body);
    final isMutation = method == 'POST' ||
        method == 'PUT' ||
        method == 'PATCH' ||
        method == 'DELETE';
    final mutationFingerprint = isMutation
        ? '$method ${uri.toString()}\n${encodedBody ?? ''}'
        : null;
    final generatedMutationKey = isMutation && idempotencyKey == null;
    final mutationKey = !isMutation
        ? null
        : idempotencyKey ??
            _pendingMutationKeys.putIfAbsent(
              mutationFingerprint!,
              LifeMateApiClient.createClientRequestId,
            );
    final headers = <String, String>{
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
      if (body != null) 'Content-Type': 'application/json',
      if (mutationKey != null) 'Idempotency-Key': mutationKey,
    };
    final maxAttempts = retryable || isMutation ? 3 : 1;
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
        milliseconds: min(
          _requestTimeout.inMilliseconds,
          remainingMilliseconds,
        ),
      );

      late final http.Response response;
      try {
        response = await _sendOnce(
          method: method,
          uri: uri,
          headers: headers,
          encodedBody: encodedBody,
        ).timeout(attemptTimeout);
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

      final retryResponse = _shouldRetryResponse(response);
      if (attempt < maxAttempts &&
          retryResponse &&
          await _waitBeforeRetry(attempt, budget, response: response)) {
        continue;
      }

      try {
        final decoded = _decodeResponse(response);
        if (generatedMutationKey) {
          _pendingMutationKeys.remove(mutationFingerprint);
        }
        return decoded;
      } on LifeMateApiException {
        if (generatedMutationKey && !retryResponse) {
          _pendingMutationKeys.remove(mutationFingerprint);
        }
        rethrow;
      }
    }

    throw StateError('LifeMate retry loop exited unexpectedly.');
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

  Future<http.Response> _sendOnce({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    required String? encodedBody,
  }) {
    switch (method) {
      case 'GET':
        return _http.get(uri, headers: headers);
      case 'POST':
        return _http.post(uri, headers: headers, body: encodedBody);
      case 'PUT':
        return _http.put(uri, headers: headers, body: encodedBody);
      case 'PATCH':
        return _http.patch(uri, headers: headers, body: encodedBody);
      case 'DELETE':
        return _http.delete(uri, headers: headers);
      default:
        throw ArgumentError.value(method, 'method', 'Unsupported HTTP method');
    }
  }

  dynamic _decodeResponse(http.Response response) {
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
    if (response.statusCode >= 200 && response.statusCode < 300) return decoded;

    final problem = decoded is Map<String, dynamic> ? decoded : const {};
    throw LifeMateApiException(
      statusCode: response.statusCode,
      code: (problem['code'] ?? problem['title'] ?? 'request_failed').toString(),
      message: (problem['detail'] ?? 'LifeMate request failed.').toString(),
    );
  }

  static Map<String, dynamic> _asObject(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return const <String, dynamic>{};
  }

  static String _date(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
