import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:lifemate_client/lifemate_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'women_daily_log_visuals.dart';

class WomenDailyLogApi {
  WomenDailyLogApi({required Uri baseUri, required String? Function() accessToken, http.Client? httpClient})
      : _baseUri = baseUri, _accessToken = accessToken, _http = httpClient ?? http.Client();

  factory WomenDailyLogApi.fromEnvironment({http.Client? httpClient}) {
    final config = AppConfig.fromEnvironment();
    return WomenDailyLogApi(
      baseUri: config.apiBaseUri,
      accessToken: () => Supabase.instance.client.auth.currentSession?.accessToken,
      httpClient: httpClient,
    );
  }

  final Uri _baseUri;
  final String? Function() _accessToken;
  final http.Client _http;
  static const _timeout = Duration(seconds: 20);

  Future<List<Map<String, dynamic>>> list({required DateTime from, required DateTime to}) async {
    final uri = _uri('/api/v1/women-calendar/daily-logs').replace(queryParameters: {'fromDate': _date(from), 'toDate': _date(to)});
    final value = await _request('GET', uri);
    if (value is! List) throw const FormatException('Daily log response must be a list.');
    return value.map((e) => Map<String, dynamic>.from(e as Map)).toList(growable: false);
  }

  Future<Map<String, dynamic>> save(
    WomenDailyLogDraft draft, {
    String? clientRequestId,
  }) async {
    final value = await _request(
      'PUT',
      _uri('/api/v1/women-calendar/daily-logs'),
      body: draft.toApiBody(),
      idempotencyKey: clientRequestId,
    );
    if (value is! Map) throw const FormatException('Daily log response must be an object.');
    return Map<String, dynamic>.from(value);
  }

  Future<void> delete({required DateTime loggedOn, required int version}) async {
    await _request('PUT', _uri('/api/v1/women-calendar/daily-logs'), body: {'loggedOn': _date(loggedOn), 'version': version, 'delete': true});
  }

  Future<dynamic> _request(
    String method,
    Uri uri, {
    Map<String, dynamic>? body,
    String? idempotencyKey,
  }) async {
    final token = _accessToken();
    if (token == null || token.isEmpty) {
      throw const LifeMateApiException(statusCode: 401, code: 'session_missing', message: 'Authentication session is missing.');
    }
    final headers = <String, String>{
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
      if (body != null) 'Content-Type': 'application/json',
      if (method == 'PUT')
        'Idempotency-Key': idempotencyKey ?? LifeMateApiClient.createClientRequestId(),
    };
    try {
      final response = method == 'GET'
          ? await _http.get(uri, headers: headers).timeout(_timeout)
          : await _http.put(uri, headers: headers, body: jsonEncode(body)).timeout(_timeout);
      final decoded = response.body.trim().isEmpty ? null : jsonDecode(response.body);
      if (response.statusCode >= 200 && response.statusCode < 300) return decoded;
      final problem = decoded is Map<String, dynamic> ? decoded : const <String, dynamic>{};
      throw LifeMateApiException(
        statusCode: response.statusCode,
        code: problem['code']?.toString() ?? 'request_failed',
        message: problem['detail']?.toString() ?? problem['message']?.toString() ?? 'Women Health daily log request failed.',
      );
    } on TimeoutException {
      throw const LifeMateApiException(statusCode: 0, code: 'network_timeout', message: 'Women Health daily log request timed out.');
    } on http.ClientException {
      throw const LifeMateApiException(statusCode: 0, code: 'network_unavailable', message: 'Women Health daily log request could not reach LifeMate API.');
    }
  }

  Uri _uri(String path) => _baseUri.replace(path: '${_baseUri.path.replaceFirst(RegExp(r'/$'), '')}$path');
  static String _date(DateTime value) => '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  void close() => _http.close();
}
