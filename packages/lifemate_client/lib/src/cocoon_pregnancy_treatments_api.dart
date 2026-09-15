import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'lifemate_api_client.dart'
    show AccessTokenProvider, LifeMateApiException;

/// Read-only Cocoon projection over the canonical LifeMate treatment domain.
///
/// Mutations intentionally remain owned by the shared treatment APIs. Cocoon
/// must not create a second medication/treatment schedule or adherence path.
class CocoonPregnancyTreatmentContext {
  const CocoonPregnancyTreatmentContext({
    required this.contractVersion,
    required this.episodeId,
    required this.fromDate,
    required this.toDate,
    required this.treatmentPlans,
    required this.doseOccurrences,
    required this.mutationAuthority,
  });

  factory CocoonPregnancyTreatmentContext.fromJson(Map<String, dynamic> json) {
    final episodeId = json['episodeId']?.toString().trim() ?? '';
    final fromDate = json['fromDate']?.toString().trim() ?? '';
    final toDate = json['toDate']?.toString().trim() ?? '';
    final plans = json['treatmentPlans'];
    final occurrences = json['doseOccurrences'];
    final authority = json['mutationAuthority']?.toString().trim() ?? '';
    if (episodeId.isEmpty ||
        fromDate.isEmpty ||
        toDate.isEmpty ||
        plans is! List ||
        occurrences is! List ||
        authority != 'canonical_treatment_api') {
      throw const FormatException('Invalid Cocoon pregnancy treatment context.');
    }

    List<Map<String, dynamic>> objects(List values) => values
        .whereType<Map>()
        .map((value) => Map<String, dynamic>.unmodifiable(
              Map<String, dynamic>.from(value),
            ))
        .toList(growable: false);

    return CocoonPregnancyTreatmentContext(
      contractVersion: (json['contractVersion'] as num?)?.toInt() ?? 0,
      episodeId: episodeId,
      fromDate: fromDate,
      toDate: toDate,
      treatmentPlans: objects(plans),
      doseOccurrences: objects(occurrences),
      mutationAuthority: authority,
    );
  }

  final int contractVersion;
  final String episodeId;
  final String fromDate;
  final String toDate;
  final List<Map<String, dynamic>> treatmentPlans;
  final List<Map<String, dynamic>> doseOccurrences;
  final String mutationAuthority;
}

class CocoonPregnancyTreatmentsApiClient {
  CocoonPregnancyTreatmentsApiClient({
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

  Future<CocoonPregnancyTreatmentContext> list({
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    final token = _accessToken();
    if (token == null || token.isEmpty) {
      throw const LifeMateApiException(
        statusCode: 401,
        code: 'session_missing',
        message: 'Authentication session is missing.',
      );
    }

    final uri = _resolve('/api/v1/cocoon/pregnancy/treatments').replace(
      queryParameters: {'fromDate': _date(fromDate), 'toDate': _date(toDate)},
    );
    late http.Response response;
    try {
      response = await _http.get(
        uri,
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(_timeout);
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
    return CocoonPregnancyTreatmentContext.fromJson(decoded);
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
