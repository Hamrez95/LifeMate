import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:lifemate_client/lifemate_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class WomenCircleApi {
  WomenCircleApi({required Uri baseUri, required String? Function() accessToken, http.Client? httpClient})
      : _baseUri = baseUri, _accessToken = accessToken, _http = httpClient ?? http.Client();

  factory WomenCircleApi.fromEnvironment({http.Client? httpClient}) {
    final config = AppConfig.fromEnvironment();
    return WomenCircleApi(
      baseUri: config.apiBaseUri,
      accessToken: () => Supabase.instance.client.auth.currentSession?.accessToken,
      httpClient: httpClient,
    );
  }

  final Uri _baseUri;
  final String? Function() _accessToken;
  final http.Client _http;
  static const _timeout = Duration(seconds: 20);

  Future<Map<String, dynamic>> command(Map<String, dynamic> command) async {
    final token = _accessToken();
    if (token == null || token.isEmpty) {
      throw const LifeMateApiException(statusCode: 401, code: 'session_missing', message: 'Authentication session is missing.');
    }
    final uri = _baseUri.replace(path: '${_baseUri.path.replaceFirst(RegExp(r'/$'), '')}/api/v1/women-calendar/profile');
    try {
      final response = await _http.patch(
        uri,
        headers: <String, String>{
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(<String, dynamic>{'circleCommand': command}),
      ).timeout(_timeout);
      final decoded = response.body.trim().isEmpty ? null : jsonDecode(response.body);
      if (response.statusCode >= 200 && response.statusCode < 300 && decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
      final problem = decoded is Map<String, dynamic> ? decoded : const <String, dynamic>{};
      throw LifeMateApiException(
        statusCode: response.statusCode,
        code: problem['code']?.toString() ?? 'request_failed',
        message: problem['detail']?.toString() ?? problem['message']?.toString() ?? 'Women Health Circle request failed.',
      );
    } on TimeoutException {
      throw const LifeMateApiException(statusCode: 0, code: 'network_timeout', message: 'Women Health Circle request timed out.');
    } on http.ClientException {
      throw const LifeMateApiException(statusCode: 0, code: 'network_unavailable', message: 'Women Health Circle request could not reach LifeMate API.');
    }
  }

  void close() => _http.close();
}
