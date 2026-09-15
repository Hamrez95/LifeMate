import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'health_observations_api.dart' show LifeMateHealthObservation;
import 'lifemate_api_client.dart'
    show AccessTokenProvider, LifeMateApiException;

enum CocoonPregnancyMeasurementType {
  weight('weight'),
  bloodPressure('blood_pressure'),
  bloodGlucose('blood_glucose');

  const CocoonPregnancyMeasurementType(this.wireValue);
  final String wireValue;
}

class CocoonPregnancyMeasurements {
  const CocoonPregnancyMeasurements({
    required this.contractVersion,
    required this.episodeId,
    required this.items,
  });

  factory CocoonPregnancyMeasurements.fromJson(Map<String, dynamic> json) {
    final episodeId = json['episodeId']?.toString().trim() ?? '';
    final rawItems = json['items'];
    if (episodeId.isEmpty || rawItems is! List) {
      throw const FormatException('Invalid Cocoon pregnancy measurements payload.');
    }
    return CocoonPregnancyMeasurements(
      contractVersion: (json['contractVersion'] as num?)?.toInt() ?? 0,
      episodeId: episodeId,
      items: rawItems
          .whereType<Map>()
          .map(
            (item) => LifeMateHealthObservation.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(growable: false),
    );
  }

  final int contractVersion;
  final String episodeId;
  final List<LifeMateHealthObservation> items;
}

class CocoonPregnancyMeasurementCreateResult {
  const CocoonPregnancyMeasurementCreateResult({
    required this.contractVersion,
    required this.episodeId,
    required this.observation,
  });

  factory CocoonPregnancyMeasurementCreateResult.fromJson(
    Map<String, dynamic> json,
  ) {
    final episodeId = json['episodeId']?.toString().trim() ?? '';
    final rawObservation = json['observation'];
    if (episodeId.isEmpty || rawObservation is! Map) {
      throw const FormatException('Invalid Cocoon pregnancy measurement response.');
    }
    return CocoonPregnancyMeasurementCreateResult(
      contractVersion: (json['contractVersion'] as num?)?.toInt() ?? 0,
      episodeId: episodeId,
      observation: LifeMateHealthObservation.fromJson(
        Map<String, dynamic>.from(rawObservation),
      ),
    );
  }

  final int contractVersion;
  final String episodeId;
  final LifeMateHealthObservation observation;
}

class CocoonPregnancyMeasurementLinkResult {
  const CocoonPregnancyMeasurementLinkResult({
    required this.contractVersion,
    required this.episodeId,
    required this.observationId,
  });

  factory CocoonPregnancyMeasurementLinkResult.fromJson(
    Map<String, dynamic> json,
  ) {
    final episodeId = json['episodeId']?.toString().trim() ?? '';
    final observationId = json['observationId']?.toString().trim() ?? '';
    if (episodeId.isEmpty || observationId.isEmpty) {
      throw const FormatException('Invalid Cocoon pregnancy measurement link response.');
    }
    return CocoonPregnancyMeasurementLinkResult(
      contractVersion: (json['contractVersion'] as num?)?.toInt() ?? 0,
      episodeId: episodeId,
      observationId: observationId,
    );
  }

  final int contractVersion;
  final String episodeId;
  final String observationId;
}

/// Narrow Cocoon adapter over the canonical LifeMate health-observation domain.
///
/// This client never maintains a second measurement model or applies clinical
/// interpretation. Values, units, provenance, validation and persistence remain
/// owned by the canonical health-observation service.
class CocoonPregnancyMeasurementsApiClient {
  CocoonPregnancyMeasurementsApiClient({
    required Uri baseUri,
    required AccessTokenProvider accessToken,
    http.Client? httpClient,
  }) : _baseUri = baseUri,
       _accessToken = accessToken,
       _http = httpClient ?? http.Client();

  final Uri _baseUri;
  final AccessTokenProvider _accessToken;
  final http.Client _http;
  static const _timeout = Duration(seconds: 20);

  Future<CocoonPregnancyMeasurements> list({
    required DateTime fromDate,
    required DateTime toDate,
  }) async => CocoonPregnancyMeasurements.fromJson(
    await _object(
      'GET',
      '/api/v1/cocoon/pregnancy/measurements',
      query: {'fromDate': _date(fromDate), 'toDate': _date(toDate)},
    ),
  );

  Future<CocoonPregnancyMeasurementCreateResult> create({
    required String clientRequestId,
    required CocoonPregnancyMeasurementType type,
    required double valuePrimary,
    double? valueSecondary,
    String? note,
    required DateTime observedAtUtc,
    required DateTime observedLocalDate,
    required String timeZone,
  }) async {
    final requestId = _required(clientRequestId, 'clientRequestId');
    final normalizedNote = note?.trim();
    final body = <String, dynamic>{
      'clientRequestId': requestId,
      'observationType': type.wireValue,
      'valuePrimary': valuePrimary,
      if (valueSecondary != null) 'valueSecondary': valueSecondary,
      if (normalizedNote?.isNotEmpty ?? false) 'note': normalizedNote,
      'observedAtUtc': observedAtUtc.toUtc().toIso8601String(),
      'observedLocalDate': _date(observedLocalDate),
      'timeZone': _required(timeZone, 'timeZone'),
    };
    return CocoonPregnancyMeasurementCreateResult.fromJson(
      await _object(
        'POST',
        '/api/v1/cocoon/pregnancy/measurements',
        body: body,
        idempotencyKey: requestId,
      ),
    );
  }

  Future<CocoonPregnancyMeasurementLinkResult> linkExisting({
    required String clientRequestId,
    required String observationId,
  }) async {
    final requestId = _required(clientRequestId, 'clientRequestId');
    return CocoonPregnancyMeasurementLinkResult.fromJson(
      await _object(
        'POST',
        '/api/v1/cocoon/pregnancy/measurement-links',
        body: {'observationId': _required(observationId, 'observationId')},
        idempotencyKey: requestId,
      ),
    );
  }

  Future<Map<String, dynamic>> _object(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
    String? idempotencyKey,
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
      if (idempotencyKey != null) 'Idempotency-Key': idempotencyKey,
    };

    late http.Response response;
    try {
      response = switch (method) {
        'GET' => await _http.get(uri, headers: headers).timeout(_timeout),
        'POST' => await _http
            .post(uri, headers: headers, body: jsonEncode(body))
            .timeout(_timeout),
        _ => throw ArgumentError.value(method, 'method', 'Unsupported method'),
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

    dynamic decoded;
    try {
      decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    } on FormatException {
      if (response.statusCode >= 200 && response.statusCode < 300) rethrow;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final problem = decoded is Map<String, dynamic> ? decoded : const {};
      throw LifeMateApiException(
        statusCode: response.statusCode,
        code: (problem['code'] ?? problem['title'] ?? 'request_failed')
            .toString(),
        message: (problem['detail'] ?? 'LifeMate request failed.').toString(),
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('LifeMate API returned a non-object payload.');
    }
    return decoded;
  }

  static String _required(String value, String name) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(value, name, 'must not be empty.');
    }
    return normalized;
  }

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  Uri _resolve(String path) {
    final base = _baseUri.toString().replaceFirst(RegExp(r'/+$'), '');
    final relative = path.replaceFirst(RegExp(r'^/+'), '');
    return Uri.parse('$base/$relative');
  }

  void close() => _http.close();
}
