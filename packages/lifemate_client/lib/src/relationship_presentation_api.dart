import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config.dart';
import 'lifemate_api_client.dart';

class LifeMateRelationshipPresentationApi {
  LifeMateRelationshipPresentationApi({
    required Uri baseUri,
    required String? Function() accessToken,
    http.Client? httpClient,
  })  : _baseUri = baseUri,
        _accessToken = accessToken,
        _http = httpClient ?? http.Client();

  factory LifeMateRelationshipPresentationApi.fromEnvironment({
    http.Client? httpClient,
  }) {
    final config = AppConfig.fromEnvironment();
    return LifeMateRelationshipPresentationApi(
      baseUri: config.apiBaseUri,
      accessToken: () => Supabase.instance.client.auth.currentSession?.accessToken,
      httpClient: httpClient,
    );
  }

  final Uri _baseUri;
  final String? Function() _accessToken;
  final http.Client _http;
  static const _timeout = Duration(seconds: 20);

  Future<Map<String, dynamic>> update({
    required String relationshipId,
    required String relationshipType,
    String? displayName,
  }) async {
    final token = _accessToken();
    if (token == null || token.isEmpty) {
      throw const LifeMateApiException(
        statusCode: 401,
        code: 'session_missing',
        message: 'Authentication session is missing.',
      );
    }
    final base = _baseUri.toString().replaceFirst(RegExp(r'/+$'), '');
    // Uses the existing authenticated relationship mutation transport. The
    // server dispatches the nested presentation object to a presentation-only
    // path; it is never interpreted as an authorization permission.
    final uri = Uri.parse(
      '$base/api/v1/care/relationships/$relationshipId/permissions',
    );
    try {
      final response = await _http
          .patch(
            uri,
            headers: {
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
              'Idempotency-Key': LifeMateApiClient.createClientRequestId(),
            },
            body: jsonEncode({
              'presentation': {
                'relationshipType': relationshipType,
                'displayName': displayName?.trim().isEmpty == true
                    ? null
                    : displayName?.trim(),
              },
            }),
          )
          .timeout(_timeout);
      dynamic decoded;
      if (response.body.isNotEmpty) decoded = jsonDecode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final problem = decoded is Map
            ? Map<String, dynamic>.from(decoded)
            : const <String, dynamic>{};
        throw LifeMateApiException(
          statusCode: response.statusCode,
          code: problem['code']?.toString() ?? 'request_failed',
          message: problem['detail']?.toString() ??
              problem['message']?.toString() ??
              'Relationship presentation update failed.',
        );
      }
      if (decoded is! Map) {
        throw const FormatException(
          'Relationship presentation response must be an object.',
        );
      }
      return Map<String, dynamic>.from(decoded);
    } on TimeoutException {
      throw const LifeMateApiException(
        statusCode: 0,
        code: 'network_timeout',
        message: 'Relationship presentation request timed out.',
      );
    } on http.ClientException {
      throw const LifeMateApiException(
        statusCode: 0,
        code: 'network_unavailable',
        message: 'Relationship presentation service is unavailable.',
      );
    }
  }

  void close() => _http.close();
}
