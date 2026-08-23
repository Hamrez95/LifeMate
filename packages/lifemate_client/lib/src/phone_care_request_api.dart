import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config.dart';
import 'lifemate_api_client.dart';

typedef PhoneCareRequestAccessTokenProvider = String? Function();

/// Narrow client for the caregiver -> WellMate phone care-request journey.
///
/// This intentionally targets `lifemate-api`; it does not call Kavenegar,
/// create invitation tokens, or expose target-account existence.
class PhoneCareRequestApi {
  PhoneCareRequestApi({
    required Uri baseUri,
    required PhoneCareRequestAccessTokenProvider accessToken,
    http.Client? httpClient,
  }) : _baseUri = baseUri,
       _accessToken = accessToken,
       _http = httpClient ?? http.Client();

  factory PhoneCareRequestApi.fromEnvironment({http.Client? httpClient}) {
    final config = AppConfig.fromEnvironment();
    return PhoneCareRequestApi(
      baseUri: config.apiBaseUri,
      accessToken: () => Supabase.instance.client.auth.currentSession?.accessToken,
      httpClient: httpClient,
    );
  }

  final Uri _baseUri;
  final PhoneCareRequestAccessTokenProvider _accessToken;
  final http.Client _http;
  static const _timeout = Duration(seconds: 20);

  Future<Map<String, dynamic>> create({required String phone}) async {
    final token = _accessToken();
    if (token == null || token.isEmpty) {
      throw const LifeMateApiException(
        statusCode: 401,
        code: 'session_missing',
        message: 'Authentication session is missing.',
      );
    }

    final uri = _resolve('/api/v1/care/requests');
    final requestId = LifeMateApiClient.createClientRequestId();
    late final http.Response response;
    try {
      response = await _http
          .post(
            uri,
            headers: {
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
              'Idempotency-Key': requestId,
            },
            body: jsonEncode({
              'contactType': 'phone',
              'contact': phone.trim(),
              'consentVersion': 'care-caregiver-request-v1',
              'confirmConsent': true,
            }),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const LifeMateApiException(
        statusCode: 0,
        code: 'network_timeout',
        message: 'LifeMate request timed out.',
      );
    } on http.ClientException {
      throw const LifeMateApiException(
        statusCode: 0,
        code: 'network_unavailable',
        message: 'LifeMate service is unavailable.',
      );
    }

    final decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('LifeMate API returned a non-object payload.');
      }
      return decoded;
    }

    final error = decoded is Map<String, dynamic> ? decoded : const <String, dynamic>{};
    throw LifeMateApiException(
      statusCode: response.statusCode,
      code: error['code']?.toString() ?? 'request_failed',
      message: error['detail']?.toString() ??
          error['message']?.toString() ??
          'LifeMate request failed.',
    );
  }

  Uri _resolve(String path) {
    final base = _baseUri.toString().replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse('$base$path');
  }
}
