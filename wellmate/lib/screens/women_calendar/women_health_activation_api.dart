import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:lifemate_client/lifemate_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class WomenHealthActivationProfile {
  const WomenHealthActivationProfile({
    required this.version,
    required this.enabled,
    required this.lastPeriodStart,
    required this.cycleLength,
    required this.cycleLengthKnown,
    required this.periodLength,
    required this.periodLengthKnown,
    required this.regularity,
  });

  factory WomenHealthActivationProfile.fromJson(Map<String, dynamic> json) {
    return WomenHealthActivationProfile(
      version: int.tryParse(json['version']?.toString() ?? '') ?? 0,
      enabled: json['enabled'] == true,
      lastPeriodStart: DateTime.tryParse(
        json['lastPeriodStart']?.toString() ?? '',
      ),
      cycleLength: int.tryParse(json['cycleLength']?.toString() ?? '') ?? 28,
      cycleLengthKnown: json['cycleLengthKnown'] as bool?,
      periodLength: int.tryParse(json['periodLength']?.toString() ?? '') ?? 5,
      periodLengthKnown: json['periodLengthKnown'] as bool?,
      regularity: json['regularity']?.toString().trim().toLowerCase(),
    );
  }

  final int version;
  final bool enabled;
  final DateTime? lastPeriodStart;
  final int cycleLength;
  final bool? cycleLengthKnown;
  final int periodLength;
  final bool? periodLengthKnown;
  final String? regularity;
}

class WomenHealthActivationApi {
  WomenHealthActivationApi({
    required Uri baseUri,
    required String? Function() accessToken,
    http.Client? httpClient,
  }) : _baseUri = baseUri,
       _accessToken = accessToken,
       _http = httpClient ?? http.Client();

  factory WomenHealthActivationApi.fromEnvironment({http.Client? httpClient}) {
    final config = AppConfig.fromEnvironment();
    return WomenHealthActivationApi(
      baseUri: config.apiBaseUri,
      accessToken: () => Supabase.instance.client.auth.currentSession?.accessToken,
      httpClient: httpClient,
    );
  }

  final Uri _baseUri;
  final String? Function() _accessToken;
  final http.Client _http;
  static const _timeout = Duration(seconds: 20);

  Future<WomenHealthActivationProfile> getProfile() async =>
      WomenHealthActivationProfile.fromJson(
        _object(await _request('GET', '/api/v1/women-calendar/profile')),
      );

  Future<WomenHealthActivationProfile> activate({
    required WomenHealthActivationProfile current,
    required DateTime lastPeriodStart,
    required int cycleLength,
    required bool cycleLengthKnown,
    required int periodLength,
    required bool periodLengthKnown,
    required String regularity,
  }) async {
    final normalizedRegularity = regularity.trim().toLowerCase();
    if (!const {'regular', 'irregular', 'unknown'}.contains(normalizedRegularity)) {
      throw ArgumentError.value(regularity, 'regularity');
    }
    if (cycleLength < 21 || cycleLength > 45) {
      throw ArgumentError.value(cycleLength, 'cycleLength');
    }
    if (periodLength < 1 || periodLength > 10 || periodLength >= cycleLength) {
      throw ArgumentError.value(periodLength, 'periodLength');
    }

    return WomenHealthActivationProfile.fromJson(
      _object(
        await _request(
          'PATCH',
          '/api/v1/women-calendar/profile',
          body: <String, dynamic>{
            'version': current.version,
            'enabled': true,
            'lastPeriodStart': _date(lastPeriodStart),
            // Numeric values remain compatibility inputs for the existing
            // estimate engine. Known flags decide whether UI may present them
            // as user-provided truth.
            'cycleLength': cycleLength,
            'cycleLengthKnown': cycleLengthKnown,
            'periodLength': periodLength,
            'periodLengthKnown': periodLengthKnown,
            'regularity': normalizedRegularity,
            'remindersEnabled': true,
          },
        ),
      ),
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
        message: 'Women Health activation timed out.',
      );
    } on http.ClientException {
      throw const LifeMateApiException(
        statusCode: 0,
        code: 'network_unavailable',
        message: 'Women Health activation could not reach LifeMate API.',
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
          'Women Health activation failed.',
    );
  }

  static Map<String, dynamic> _object(dynamic value) {
    if (value is! Map) {
      throw const FormatException('LifeMate API returned a non-object payload.');
    }
    return Map<String, dynamic>.from(value);
  }

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  void close() => _http.close();
}
