import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:lifemate_client/lifemate_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class WellMateFirstValueProfile {
  const WellMateFirstValueProfile({
    required this.version,
    required this.displayName,
    required this.phoneNumber,
    required this.locale,
    required this.timeZone,
    required this.avatarKey,
    required this.presentationIntent,
    required this.state,
  });

  factory WellMateFirstValueProfile.fromJson(Map<String, dynamic> json) {
    final version = int.tryParse(json['version']?.toString() ?? '');
    if (version == null || version < 1) {
      throw const FormatException('WellMate first-value profile version is invalid.');
    }
    return WellMateFirstValueProfile(
      version: version,
      displayName: json['displayName']?.toString().trim() ?? '',
      phoneNumber: _nullable(json['phoneNumber']),
      locale: json['locale']?.toString().trim() ?? 'fa',
      timeZone: json['timeZone']?.toString().trim() ?? 'Asia/Tehran',
      avatarKey: json['avatarKey']?.toString().trim() ?? 'person_blue',
      presentationIntent: _nullable(json['presentationIntent']),
      state: _nullable(json['wellMateFirstValueState']),
    );
  }

  final int version;
  final String displayName;
  final String? phoneNumber;
  final String locale;
  final String timeZone;
  final String avatarKey;
  final String? presentationIntent;
  final String? state;

  bool get isResolved => state == 'Skipped' || state == 'Completed';

  static String? _nullable(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}

class WellMateFirstValueApi {
  WellMateFirstValueApi({
    required Uri baseUri,
    required String? Function() accessToken,
    http.Client? httpClient,
  }) : _baseUri = baseUri,
       _accessToken = accessToken,
       _http = httpClient ?? http.Client();

  factory WellMateFirstValueApi.fromEnvironment({http.Client? httpClient}) {
    final config = AppConfig.fromEnvironment();
    return WellMateFirstValueApi(
      baseUri: config.apiBaseUri,
      accessToken: () => Supabase.instance.client.auth.currentSession?.accessToken,
      httpClient: httpClient,
    );
  }

  final Uri _baseUri;
  final String? Function() _accessToken;
  final http.Client _http;
  static const _timeout = Duration(seconds: 20);

  Future<WellMateFirstValueProfile> getProfile() async {
    final value = await _request('GET', '/api/v1/me/profile');
    return WellMateFirstValueProfile.fromJson(_object(value));
  }

  Future<WellMateFirstValueProfile> setState({
    required WellMateFirstValueProfile current,
    required String state,
  }) async {
    if (state != 'Skipped' && state != 'Completed') {
      throw ArgumentError.value(state, 'state');
    }
    final value = await _request(
      'PATCH',
      '/api/v1/me/profile',
      body: <String, dynamic>{
        'version': current.version,
        'displayName': current.displayName,
        'phoneNumber': current.phoneNumber,
        'locale': current.locale,
        'timeZone': current.timeZone,
        'avatarKey': current.avatarKey,
        if (current.presentationIntent != null)
          'presentationIntent': current.presentationIntent,
        'wellMateFirstValueState': state,
      },
    );
    return WellMateFirstValueProfile.fromJson(_object(value));
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
        message: 'WellMate first-value request timed out.',
      );
    } on http.ClientException {
      throw const LifeMateApiException(
        statusCode: 0,
        code: 'network_unavailable',
        message: 'WellMate first-value request could not reach LifeMate API.',
      );
    }
    final decoded = response.body.trim().isEmpty ? null : jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) return decoded;
    final problem = decoded is Map<String, dynamic>
        ? decoded
        : const <String, dynamic>{};
    throw LifeMateApiException(
      statusCode: response.statusCode,
      code: problem['code']?.toString() ?? 'request_failed',
      message: problem['detail']?.toString() ??
          problem['message']?.toString() ??
          'WellMate first-value request failed.',
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
