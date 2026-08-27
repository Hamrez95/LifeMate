import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config.dart';
import 'lifemate_api_client.dart';

enum LifeMatePresentationIntent {
  self('Self'),
  caregiving('Caregiving'),
  both('Both');

  const LifeMatePresentationIntent(this.wireValue);
  final String wireValue;

  static LifeMatePresentationIntent? tryParse(Object? value) {
    final wire = value?.toString();
    for (final intent in values) {
      if (intent.wireValue == wire) return intent;
    }
    return null;
  }
}

class LifeMateAccountOnboardingSnapshot {
  const LifeMateAccountOnboardingSnapshot({
    required this.version,
    required this.displayName,
    required this.phoneNumber,
    required this.locale,
    required this.timeZone,
    required this.avatarKey,
    required this.presentationIntent,
    required this.completed,
  });

  factory LifeMateAccountOnboardingSnapshot.fromJson(
    Map<String, dynamic> json,
  ) {
    final version = int.tryParse(json['version']?.toString() ?? '');
    if (version == null || version < 1) {
      throw const FormatException('Profile onboarding version is invalid.');
    }
    final displayName = json['displayName']?.toString().trim() ?? '';
    final locale = json['locale']?.toString().trim() ?? '';
    final timeZone = json['timeZone']?.toString().trim() ?? '';
    final avatarKey = json['avatarKey']?.toString().trim() ?? '';
    if (locale.isEmpty || timeZone.isEmpty || avatarKey.isEmpty) {
      throw const FormatException('Profile onboarding payload is incomplete.');
    }
    return LifeMateAccountOnboardingSnapshot(
      version: version,
      displayName: displayName,
      phoneNumber: _nullableText(json['phoneNumber']),
      locale: locale,
      timeZone: timeZone,
      avatarKey: avatarKey,
      presentationIntent: LifeMatePresentationIntent.tryParse(
        json['presentationIntent'],
      ),
      completed: json['onboardingCompleted'] == true,
    );
  }

  final int version;
  final String displayName;
  final String? phoneNumber;
  final String locale;
  final String timeZone;
  final String avatarKey;
  final LifeMatePresentationIntent? presentationIntent;
  final bool completed;

  static String? _nullableText(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}

typedef LifeMateOnboardingAccessTokenProvider = String? Function();

/// Narrow client for the canonical account-onboarding contract.
///
/// It intentionally writes only the existing self-profile endpoint. Product
/// intent is presentation metadata and never creates consent, relationships or
/// healthcare authorization.
class LifeMateAccountOnboardingApi {
  LifeMateAccountOnboardingApi({
    required Uri baseUri,
    required LifeMateOnboardingAccessTokenProvider accessToken,
    http.Client? httpClient,
  }) : _baseUri = baseUri,
       _accessToken = accessToken,
       _http = httpClient ?? http.Client();

  factory LifeMateAccountOnboardingApi.fromEnvironment({http.Client? httpClient}) {
    final config = AppConfig.fromEnvironment();
    return LifeMateAccountOnboardingApi(
      baseUri: config.apiBaseUri,
      accessToken: () =>
          Supabase.instance.client.auth.currentSession?.accessToken,
      httpClient: httpClient,
    );
  }

  final Uri _baseUri;
  final LifeMateOnboardingAccessTokenProvider _accessToken;
  final http.Client _http;
  static const _timeout = Duration(seconds: 20);

  Future<LifeMateAccountOnboardingSnapshot> getSnapshot() async {
    final value = await _request('GET', '/api/v1/me/profile');
    return LifeMateAccountOnboardingSnapshot.fromJson(_object(value));
  }

  Future<LifeMateAccountOnboardingSnapshot> complete({
    required LifeMateAccountOnboardingSnapshot current,
    required String displayName,
    required LifeMatePresentationIntent intent,
  }) async {
    final normalizedName = displayName.trim();
    if (normalizedName.isEmpty || normalizedName.length > 120) {
      throw ArgumentError.value(displayName, 'displayName');
    }
    final value = await _request(
      'PATCH',
      '/api/v1/me/profile',
      body: {
        'version': current.version,
        'displayName': normalizedName,
        'phoneNumber': current.phoneNumber,
        'locale': current.locale,
        'timeZone': current.timeZone,
        'avatarKey': current.avatarKey,
        'presentationIntent': intent.wireValue,
        'completeOnboarding': true,
      },
    );
    return LifeMateAccountOnboardingSnapshot.fromJson(_object(value));
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
      if (method == 'PATCH')
        'Idempotency-Key': LifeMateApiClient.createClientRequestId(),
    };

    late final http.Response response;
    try {
      response = switch (method) {
        'GET' => await _http.get(uri, headers: headers).timeout(_timeout),
        'PATCH' => await _http
            .patch(uri, headers: headers, body: jsonEncode(body))
            .timeout(_timeout),
        _ => throw ArgumentError.value(method, 'method'),
      };
    } on TimeoutException {
      throw const LifeMateApiException(
        statusCode: 0,
        code: 'network_timeout',
        message: 'Account onboarding request timed out.',
      );
    } on http.ClientException {
      throw const LifeMateApiException(
        statusCode: 0,
        code: 'network_unavailable',
        message: 'Account onboarding could not reach LifeMate API.',
      );
    }

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
          'Account onboarding request failed.',
    );
  }

  static Map<String, dynamic> _object(dynamic value) {
    if (value is! Map) {
      throw const FormatException('LifeMate API returned a non-object payload.');
    }
    return Map<String, dynamic>.from(value);
  }

  void close() => _http.close();
}
