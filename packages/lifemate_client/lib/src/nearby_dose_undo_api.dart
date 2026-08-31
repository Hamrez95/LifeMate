import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config.dart';
import 'lifemate_api_client.dart';

class LifeMateNearbyDoseUndoResult {
  const LifeMateNearbyDoseUndoResult({
    required this.proposalId,
    required this.status,
    required this.alreadyUndone,
  });

  factory LifeMateNearbyDoseUndoResult.fromJson(Map<String, dynamic> json) =>
      LifeMateNearbyDoseUndoResult(
        proposalId: json['proposalId']?.toString() ?? '',
        status: json['status']?.toString() ?? '',
        alreadyUndone: json['alreadyUndone'] == true,
      );

  final String proposalId;
  final String status;
  final bool alreadyUndone;
}

class LifeMateNearbyDoseUndoApi {
  LifeMateNearbyDoseUndoApi({
    required Uri baseUri,
    required String? Function() accessToken,
    http.Client? httpClient,
  })  : _baseUri = baseUri,
        _accessToken = accessToken,
        _http = httpClient ?? http.Client();

  factory LifeMateNearbyDoseUndoApi.fromEnvironment({http.Client? httpClient}) {
    final config = AppConfig.fromEnvironment();
    return LifeMateNearbyDoseUndoApi(
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

  Future<LifeMateNearbyDoseUndoResult> undo(String proposalId) async {
    final token = _accessToken();
    if (token == null || token.isEmpty) {
      throw const LifeMateApiException(
        statusCode: 401,
        code: 'session_missing',
        message: 'Authentication session is missing.',
      );
    }
    final path = '/api/v1/medication-schedule-optimizations/$proposalId/undo';
    final uri = _baseUri.replace(
      path: '${_baseUri.path.replaceFirst(RegExp(r'/$'), '')}$path',
    );
    try {
      final response = await _http
          .post(
            uri,
            headers: {
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
              'Idempotency-Key': LifeMateApiClient.createClientRequestId(),
            },
            body: jsonEncode(const <String, dynamic>{'confirmed': true}),
          )
          .timeout(_timeout);
      final decoded = response.body.trim().isEmpty
          ? null
          : jsonDecode(response.body);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (decoded is! Map) {
          throw const FormatException('Medication schedule undo response is invalid.');
        }
        return LifeMateNearbyDoseUndoResult.fromJson(
          Map<String, dynamic>.from(decoded),
        );
      }
      final problem = decoded is Map<String, dynamic>
          ? decoded
          : const <String, dynamic>{};
      throw LifeMateApiException(
        statusCode: response.statusCode,
        code: problem['code']?.toString() ?? 'request_failed',
        message: problem['detail']?.toString() ??
            problem['message']?.toString() ??
            'Medication schedule undo failed.',
      );
    } on TimeoutException {
      throw const LifeMateApiException(
        statusCode: 0,
        code: 'network_timeout',
        message: 'Medication schedule undo timed out.',
      );
    } on http.ClientException {
      throw const LifeMateApiException(
        statusCode: 0,
        code: 'network_unavailable',
        message: 'Medication schedule service is unavailable.',
      );
    }
  }

  void close() => _http.close();
}
