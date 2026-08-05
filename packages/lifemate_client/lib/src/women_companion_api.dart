import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config.dart';
import 'lifemate_api_client.dart';

class WomenCompanionApi {
  WomenCompanionApi({
    required Uri baseUri,
    required String? Function() accessToken,
    http.Client? httpClient,
  })  : _baseUri = baseUri,
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

  Future<List<Map<String, dynamic>>> getDailyLogs({
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    final value = await _send(
      'GET',
      '/api/v1/women-calendar/daily-logs',
      query: {
        'fromDate': _date(fromDate),
        'toDate': _date(toDate),
      },
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
        'symptoms': symptoms.map((value) => value.trim().toLowerCase()).toList(),
        'privateNotes': _emptyToNull(privateNotes),
        'shareSummaryWithCompanion': shareSummaryWithCompanion,
      },
    );
    return Map<String, dynamic>.from(value as Map);
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    final token = _accessToken();
    if (token == null || token.isEmpty) {
      throw const LifeMateApiException(
        statusCode: 401,
        code: 'session_missing',
        message: 'Authentication session is missing.',
      );
    }
    final resolved = _baseUri.resolve(path);
    final uri = query == null
        ? resolved
        : resolved.replace(queryParameters: query);
    late http.Response response;
    try {
      final headers = <String, String>{
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
        if (body != null) 'Content-Type': 'application/json',
      };
      response = switch (method) {
        'GET' => await _http.get(uri, headers: headers).timeout(_timeout),
        'PUT' => await _http
            .put(uri, headers: headers, body: jsonEncode(body))
            .timeout(_timeout),
        _ => throw ArgumentError.value(method, 'method'),
      };
    } on TimeoutException {
      throw const LifeMateApiException(
        statusCode: 408,
        code: 'request_timeout',
        message: 'The request timed out.',
      );
    }

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
        message: problem['message']?.toString() ?? 'The request failed.',
      );
    }
    return decoded;
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
