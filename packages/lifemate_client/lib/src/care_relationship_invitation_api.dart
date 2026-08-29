import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config.dart';
import 'lifemate_api_client.dart';
import 'relationship_presentation.dart';

class LifeMateCareRelationshipInvitationApi {
  LifeMateCareRelationshipInvitationApi({
    required Uri baseUri,
    required String? Function() accessToken,
    http.Client? httpClient,
  })  : _baseUri = baseUri,
        _accessToken = accessToken,
        _http = httpClient ?? http.Client();

  factory LifeMateCareRelationshipInvitationApi.fromEnvironment({
    http.Client? httpClient,
  }) {
    final config = AppConfig.fromEnvironment();
    return LifeMateCareRelationshipInvitationApi(
      baseUri: config.apiBaseUri,
      accessToken: () => Supabase.instance.client.auth.currentSession?.accessToken,
      httpClient: httpClient,
    );
  }

  final Uri _baseUri;
  final String? Function() _accessToken;
  final http.Client _http;
  static const _timeout = Duration(seconds: 20);

  Future<Map<String, dynamic>> createPhoneInvitation({
    required String phone,
    required String relationshipType,
    String? caregiverDisplayName,
  }) async {
    final normalized = LifeMateRelationshipPresentationPolicy.fromRaw(
      relationshipType,
    ).storageValue;
    if (!const {'partner', 'family', 'child'}.contains(normalized)) {
      throw ArgumentError.value(
        relationshipType,
        'relationshipType',
        'Relationship type must be partner, family or child.',
      );
    }
    return _post(
      '/api/v1/care/invitations',
      {
        'contactType': 'phone',
        'contact': phone.trim(),
        'relationshipType': normalized,
        'displayName': _emptyToNull(caregiverDisplayName),
        'consentVersion': 'care-patient-consent-v1',
        'confirmConsent': true,
      },
    );
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final token = _accessToken();
    if (token == null || token.isEmpty) {
      throw const LifeMateApiException(
        statusCode: 401,
        code: 'session_missing',
        message: 'Authentication session is missing.',
      );
    }
    final base = _baseUri.toString().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base$path');
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
            body: jsonEncode(body),
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
              'Care invitation failed.',
        );
      }
      if (decoded is! Map) {
        throw const FormatException('Care invitation response must be an object.');
      }
      return Map<String, dynamic>.from(decoded);
    } on TimeoutException {
      throw const LifeMateApiException(
        statusCode: 0,
        code: 'network_timeout',
        message: 'Care invitation request timed out.',
      );
    } on http.ClientException {
      throw const LifeMateApiException(
        statusCode: 0,
        code: 'network_unavailable',
        message: 'Care invitation service is unavailable.',
      );
    }
  }

  static String? _emptyToNull(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  void close() => _http.close();
}
