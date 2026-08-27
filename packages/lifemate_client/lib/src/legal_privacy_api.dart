import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config.dart';
import 'lifemate_api_client.dart';

class LifeMateLegalDocument {
  const LifeMateLegalDocument({
    required this.id,
    required this.purpose,
    required this.version,
    required this.title,
    required this.documentHash,
    required this.contentUri,
    required this.accepted,
  });

  factory LifeMateLegalDocument.fromJson(Map<String, dynamic> json) =>
      LifeMateLegalDocument(
        id: json['id']?.toString() ?? '',
        purpose: json['purpose']?.toString() ?? '',
        version: json['version']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        documentHash: json['documentHash']?.toString() ?? '',
        contentUri: _nullable(json['contentUri']),
        accepted: json['accepted'] == true,
      );

  final String id;
  final String purpose;
  final String version;
  final String title;
  final String documentHash;
  final String? contentUri;
  final bool accepted;

  Map<String, String> acceptancePayload() => {
    'documentId': id,
    'documentHash': documentHash,
  };

  static String? _nullable(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}

class LifeMateRegistrationStatus {
  const LifeMateRegistrationStatus({
    required this.completed,
    required this.registrationPolicyVersion,
    required this.requiredDocuments,
  });

  factory LifeMateRegistrationStatus.fromJson(Map<String, dynamic> json) =>
      LifeMateRegistrationStatus(
        completed: json['completed'] == true,
        registrationPolicyVersion:
            json['registrationPolicyVersion']?.toString(),
        requiredDocuments: (json['requiredDocuments'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((value) => LifeMateLegalDocument.fromJson(
                  Map<String, dynamic>.from(value),
                ))
            .toList(growable: false),
      );

  final bool completed;
  final String? registrationPolicyVersion;
  final List<LifeMateLegalDocument> requiredDocuments;
}

class LifeMatePrivacyPreference {
  const LifeMatePrivacyPreference({
    required this.purpose,
    required this.category,
    required this.channel,
    required this.policyVersion,
    required this.enabled,
    required this.explicit,
    required this.userMutable,
    required this.description,
  });

  factory LifeMatePrivacyPreference.fromJson(Map<String, dynamic> json) =>
      LifeMatePrivacyPreference(
        purpose: json['purpose']?.toString() ?? '',
        category: json['category']?.toString() ?? '',
        channel: json['channel']?.toString(),
        policyVersion: json['policyVersion']?.toString() ?? '',
        enabled: json['enabled'] == true,
        explicit: json['explicit'] == true,
        userMutable: json['userMutable'] == true,
        description: json['description']?.toString() ?? '',
      );

  final String purpose;
  final String category;
  final String? channel;
  final String policyVersion;
  final bool enabled;
  final bool explicit;
  final bool userMutable;
  final String description;
}

typedef LifeMateLegalPrivacyTokenProvider = String? Function();

class LifeMateLegalPrivacyApi {
  LifeMateLegalPrivacyApi({
    required Uri baseUri,
    required LifeMateLegalPrivacyTokenProvider accessToken,
    http.Client? httpClient,
  }) : _baseUri = baseUri,
       _accessToken = accessToken,
       _http = httpClient ?? http.Client();

  factory LifeMateLegalPrivacyApi.fromEnvironment({http.Client? httpClient}) {
    final config = AppConfig.fromEnvironment();
    return LifeMateLegalPrivacyApi(
      baseUri: config.apiBaseUri,
      accessToken: () => Supabase.instance.client.auth.currentSession?.accessToken,
      httpClient: httpClient,
    );
  }

  final Uri _baseUri;
  final LifeMateLegalPrivacyTokenProvider _accessToken;
  final http.Client _http;
  static const _timeout = Duration(seconds: 20);

  Future<LifeMateRegistrationStatus> registrationStatus() async =>
      LifeMateRegistrationStatus.fromJson(
        _object(await _request('GET', '/api/v1/account/registration')),
      );

  Future<LifeMateRegistrationStatus> acceptCurrentLegalDocuments(
    List<LifeMateLegalDocument> documents,
  ) async {
    await _request(
      'POST',
      '/api/v1/account/registration/legal-acceptance',
      body: {
        'acceptances': documents
            .map((document) => document.acceptancePayload())
            .toList(growable: false),
      },
    );
    return registrationStatus();
  }

  Future<List<LifeMatePrivacyPreference>> privacyPreferences() async {
    final response = _object(
      await _request('GET', '/api/v1/account/privacy-preferences'),
    );
    return (response['items'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((item) => LifeMatePrivacyPreference.fromJson(
              Map<String, dynamic>.from(item),
            ))
        .toList(growable: false);
  }

  Future<void> setPrivacyPreference({
    required String purpose,
    required bool enabled,
  }) async {
    final normalized = purpose.trim().toLowerCase();
    if (!RegExp(r'^[a-z][a-z0-9._-]{2,79}$').hasMatch(normalized)) {
      throw ArgumentError.value(purpose, 'purpose');
    }
    await _request(
      'PATCH',
      '/api/v1/account/privacy-preferences/$normalized',
      body: {'enabled': enabled},
    );
  }

  Future<dynamic> _request(
    String method,
    String path, {
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
    final uri = _baseUri.replace(
      path: '${_baseUri.path.replaceFirst(RegExp(r'/$'), '')}$path',
    );
    final headers = <String, String>{
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
      if (body != null) 'Content-Type': 'application/json',
      if (method == 'POST' || method == 'PATCH')
        'Idempotency-Key': LifeMateApiClient.createClientRequestId(),
    };
    try {
      final response = switch (method) {
        'GET' => await _http.get(uri, headers: headers).timeout(_timeout),
        'POST' => await _http
            .post(uri, headers: headers, body: jsonEncode(body))
            .timeout(_timeout),
        'PATCH' => await _http
            .patch(uri, headers: headers, body: jsonEncode(body))
            .timeout(_timeout),
        _ => throw ArgumentError.value(method, 'method'),
      };
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
        message: problem['detail']?.toString() ??
            problem['message']?.toString() ??
            'Legal/privacy request failed.',
      );
    } on TimeoutException {
      throw const LifeMateApiException(
        statusCode: 0,
        code: 'network_timeout',
        message: 'Legal/privacy request timed out.',
      );
    } on http.ClientException {
      throw const LifeMateApiException(
        statusCode: 0,
        code: 'network_unavailable',
        message: 'Legal/privacy service is unavailable.',
      );
    }
  }

  static Map<String, dynamic> _object(dynamic value) {
    if (value is! Map) {
      throw const FormatException('LifeMate API returned a non-object payload.');
    }
    return Map<String, dynamic>.from(value);
  }

  void close() => _http.close();
}
