import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

typedef AccessTokenProvider = String? Function();

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
  String toString() => 'LifeMateApiException($statusCode, $code): $message';
}

class LifeMateApiClient {
  LifeMateApiClient({
    required Uri baseUri,
    required AccessTokenProvider accessToken,
    http.Client? httpClient,
  })  : _baseUri = baseUri,
        _accessToken = accessToken,
        _http = httpClient ?? http.Client();

  final Uri _baseUri;
  final AccessTokenProvider _accessToken;
  final http.Client _http;
  static const _requestTimeout = Duration(seconds: 20);

  static String createClientRequestId() {
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }

  Future<Map<String, dynamic>> bootstrapUser({
    required String? displayName,
    required String? email,
    String locale = 'fa',
    String timeZone = 'Asia/Tehran',
  }) async {
    final value = await _send(
      'POST',
      '/api/v1/users/bootstrap',
      body: {
        'displayName': displayName,
        'phoneNumber': null,
        'email': email,
        'locale': locale,
        'timeZone': timeZone,
      },
    );
    return _asObject(value);
  }

  Future<Map<String, dynamic>> getCurrentUser() async =>
      _asObject(await _send('GET', '/api/v1/me'));

  Future<List<Map<String, dynamic>>> getMedications() =>
      _getList('/api/v1/medications');

  Future<Map<String, dynamic>> createMedication({
    required String name,
    String? strengthText,
    String? form,
    String? notes,
  }) async =>
      _asObject(
        await _send(
          'POST',
          '/api/v1/medications',
          body: {
            'name': name.trim(),
            'strengthText': _emptyToNull(strengthText),
            'form': _emptyToNull(form),
            'notes': _emptyToNull(notes),
          },
        ),
      );

  Future<List<Map<String, dynamic>>> getTreatmentPlans() =>
      _getList('/api/v1/treatment-plans');

  Future<Map<String, dynamic>> createTreatmentPlan({
    required String medicationId,
    required String doseText,
    required DateTime startDate,
    DateTime? endDate,
    required String timeZone,
    required List<Map<String, String>> schedules,
    String? instructions,
  }) async =>
      _asObject(
        await _send(
          'POST',
          '/api/v1/treatment-plans',
          body: {
            'medicationId': medicationId,
            'doseText': doseText.trim(),
            'instructions': _emptyToNull(instructions),
            'startDate': _date(startDate),
            'endDate': endDate == null ? null : _date(endDate),
            'timeZone': timeZone,
            'schedules': schedules,
          },
        ),
      );

  Future<List<Map<String, dynamic>>> getDoseOccurrences({
    required DateTime fromDate,
    required DateTime toDate,
  }) =>
      _getList(
        '/api/v1/dose-occurrences',
        query: {
          'fromDate': _date(fromDate),
          'toDate': _date(toDate),
        },
      );

  Future<Map<String, dynamic>> reportDose({
    required String occurrenceId,
    required String clientRequestId,
    required int version,
    required String status,
    required DateTime occurredAtUtc,
  }) async {
    final value = await _send(
      'POST',
      '/api/v1/dose-occurrences/$occurrenceId/report',
      body: {
        'clientRequestId': clientRequestId,
        'version': version,
        'status': status,
        'occurredAtUtc': occurredAtUtc.toUtc().toIso8601String(),
      },
    );
    return _asObject(value);
  }

  Future<List<Map<String, dynamic>>> getCareRelationships() =>
      _getList('/api/v1/care/relationships');

  Future<Map<String, dynamic>> createCareInvitation({
    required String email,
  }) async =>
      _asObject(
        await _send(
          'POST',
          '/api/v1/care/invitations',
          body: {
            'contactType': 'email',
            'contact': email.trim(),
            'consentVersion': 'care-patient-consent-v1',
            'confirmConsent': true,
          },
        ),
      );

  Future<List<Map<String, dynamic>>> getOutgoingCareInvitations() =>
      _getList('/api/v1/care/invitations');

  Future<Map<String, dynamic>> acceptCareInvitation({
    required String token,
  }) async =>
      _asObject(
        await _send(
          'POST',
          '/api/v1/care/invitations/accept',
          body: {
            'token': token.trim(),
            'consentVersion': 'care-caregiver-consent-v1',
            'confirmConsent': true,
          },
        ),
      );

  Future<void> revokeCareRelationship({
    required String relationshipId,
  }) async {
    await _send('DELETE', '/api/v1/care/relationships/$relationshipId');
  }

  Future<List<Map<String, dynamic>>> getCareRecipientDoseOccurrences({
    required String patientUserId,
    required DateTime fromDate,
    required DateTime toDate,
  }) =>
      _getList(
        '/api/v1/care/patients/$patientUserId/dose-occurrences',
        query: {
          'fromDate': _date(fromDate),
          'toDate': _date(toDate),
        },
      );

  Future<List<Map<String, dynamic>>> _getList(
    String path, {
    Map<String, String>? query,
  }) async {
    final value = await _send('GET', path, query: query);
    if (value is! List) {
      throw const FormatException('LifeMate API returned a non-list payload.');
    }
    return value.map(_asObject).toList(growable: false);
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
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
    };
    late final http.Response response;
    switch (method) {
      case 'GET':
        response =
            await _http.get(uri, headers: headers).timeout(_requestTimeout);
        break;
      case 'POST':
        response = await _http.post(
          uri,
          headers: headers,
          body: body == null ? null : jsonEncode(body),
        ).timeout(_requestTimeout);
        break;
      case 'DELETE':
        response =
            await _http.delete(uri, headers: headers).timeout(_requestTimeout);
        break;
      default:
        throw ArgumentError.value(method, 'method', 'Unsupported HTTP method');
    }

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
    throw const FormatException('LifeMate API returned a non-object payload.');
  }

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  Uri _resolve(String path) {
    final base = _baseUri.toString().replaceFirst(RegExp(r'/+$'), '');
    final relative = path.replaceFirst(RegExp(r'^/+'), '');
    return Uri.parse('$base/$relative');
  }

  static String? _emptyToNull(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  void close() => _http.close();
}
