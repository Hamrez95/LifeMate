import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config.dart';
import 'lifemate_api_client.dart';

typedef LifeMateHealthAccessTokenProvider = String? Function();

class LifeMateHealthObservation {
  const LifeMateHealthObservation({
    required this.id,
    required this.personId,
    required this.observationType,
    required this.valuePrimary,
    required this.valueSecondary,
    required this.unitPrimary,
    required this.unitSecondary,
    required this.note,
    required this.observedAtUtc,
    required this.observedLocalDate,
    required this.timeZone,
    required this.sourceCategory,
    required this.sourceProvider,
    required this.version,
  });

  factory LifeMateHealthObservation.fromJson(Map<String, dynamic> json) {
    final observedAt = DateTime.tryParse(
      json['observedAtUtc']?.toString() ?? '',
    );
    final localDate = DateTime.tryParse(
      json['observedLocalDate']?.toString() ?? '',
    );
    if (observedAt == null || localDate == null) {
      throw const FormatException('Health observation contains invalid dates.');
    }
    return LifeMateHealthObservation(
      id: json['id']?.toString() ?? '',
      personId: json['personId']?.toString() ?? '',
      observationType: json['observationType']?.toString() ?? '',
      valuePrimary: _number(json['valuePrimary']),
      valueSecondary: _number(json['valueSecondary']),
      unitPrimary: json['unitPrimary']?.toString(),
      unitSecondary: json['unitSecondary']?.toString(),
      note: json['note']?.toString(),
      observedAtUtc: observedAt.toUtc(),
      observedLocalDate: DateTime(
        localDate.year,
        localDate.month,
        localDate.day,
      ),
      timeZone: json['timeZone']?.toString() ?? 'Asia/Tehran',
      sourceCategory: json['sourceCategory']?.toString() ?? '',
      sourceProvider: json['sourceProvider']?.toString() ?? '',
      version: int.tryParse(json['version']?.toString() ?? '') ?? 1,
    );
  }

  final String id;
  final String personId;
  final String observationType;
  final double? valuePrimary;
  final double? valueSecondary;
  final String? unitPrimary;
  final String? unitSecondary;
  final String? note;
  final DateTime observedAtUtc;
  final DateTime observedLocalDate;
  final String timeZone;
  final String sourceCategory;
  final String sourceProvider;
  final int version;

  static double? _number(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }
}

class LifeMateHealthApi {
  LifeMateHealthApi({
    required Uri baseUri,
    required LifeMateHealthAccessTokenProvider accessToken,
    http.Client? httpClient,
  }) : _baseUri = baseUri,
       _accessToken = accessToken,
       _http = httpClient ?? http.Client();

  factory LifeMateHealthApi.fromEnvironment({http.Client? httpClient}) {
    final config = AppConfig.fromEnvironment();
    return LifeMateHealthApi(
      baseUri: config.apiBaseUri,
      accessToken: () =>
          Supabase.instance.client.auth.currentSession?.accessToken,
      httpClient: httpClient,
    );
  }

  final Uri _baseUri;
  final LifeMateHealthAccessTokenProvider _accessToken;
  final http.Client _http;
  static const _timeout = Duration(seconds: 20);

  Future<List<LifeMateHealthObservation>> listObservations({
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    final value = await _request(
      'GET',
      '/api/v1/health/observations',
      query: {'fromDate': _date(fromDate), 'toDate': _date(toDate)},
    );
    if (value is! List) {
      throw const FormatException(
        'Health observations response is not a list.',
      );
    }
    return value
        .map((entry) => LifeMateHealthObservation.fromJson(_object(entry)))
        .toList(growable: false);
  }

  Future<LifeMateHealthObservation> createObservation({
    required String observationType,
    double? valuePrimary,
    double? valueSecondary,
    String? note,
    required DateTime observedAtUtc,
    required DateTime observedLocalDate,
    required String timeZone,
    String? clientRequestId,
  }) async {
    final value = await _request(
      'POST',
      '/api/v1/health/observations',
      body: {
        'clientRequestId':
            clientRequestId ?? LifeMateApiClient.createClientRequestId(),
        'observationType': observationType.trim().toLowerCase(),
        'valuePrimary': valuePrimary,
        'valueSecondary': valueSecondary,
        'note': _emptyToNull(note),
        'observedAtUtc': observedAtUtc.toUtc().toIso8601String(),
        'observedLocalDate': _date(observedLocalDate),
        'timeZone': timeZone.trim(),
      },
    );
    return LifeMateHealthObservation.fromJson(_object(value));
  }

  Future<void> deleteObservation({required String observationId}) async {
    await _request('DELETE', '/api/v1/health/observations/$observationId');
  }

  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, String>? query,
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

    var uri = _resolve(path);
    if (query != null) uri = uri.replace(queryParameters: query);
    final headers = <String, String>{
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
      if (body != null) 'Content-Type': 'application/json',
    };

    late final http.Response response;
    try {
      response = switch (method) {
        'GET' => await _http.get(uri, headers: headers).timeout(_timeout),
        'POST' =>
          await _http
              .post(uri, headers: headers, body: jsonEncode(body))
              .timeout(_timeout),
        'DELETE' => await _http.delete(uri, headers: headers).timeout(_timeout),
        _ => throw ArgumentError.value(method, 'method'),
      };
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

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      return jsonDecode(response.body);
    }
    dynamic decoded;
    try {
      decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    } on FormatException {
      decoded = null;
    }
    final problem = decoded is Map<String, dynamic> ? decoded : const {};
    throw LifeMateApiException(
      statusCode: response.statusCode,
      code: (problem['code'] ?? problem['title'] ?? 'request_failed')
          .toString(),
      message: (problem['detail'] ?? 'LifeMate request failed.').toString(),
    );
  }

  Uri _resolve(String path) {
    final base = _baseUri.toString().replaceFirst(RegExp(r'/+$'), '');
    final relative = path.replaceFirst(RegExp(r'^/+'), '');
    return Uri.parse('$base/$relative');
  }

  static Map<String, dynamic> _object(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    throw const FormatException('LifeMate API returned a non-object payload.');
  }

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static String? _emptyToNull(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  void close() => _http.close();
}
