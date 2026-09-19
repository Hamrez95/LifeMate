import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'lifemate_api_client.dart'
    show AccessTokenProvider, LifeMateApiException;

class CocoonPregnancyTreatmentPlanProjection {
  const CocoonPregnancyTreatmentPlanProjection({
    required this.id,
    required this.medicationId,
    required this.medicationName,
    required this.doseText,
    required this.status,
    required this.version,
    this.strengthText,
  });

  factory CocoonPregnancyTreatmentPlanProjection.fromJson(
    Map<String, dynamic> json,
  ) {
    final medication = json['medication'];
    if (medication is! Map) {
      throw const FormatException(
        'Invalid Cocoon pregnancy treatment medication projection.',
      );
    }
    final medicationJson = Map<String, dynamic>.from(medication);
    return CocoonPregnancyTreatmentPlanProjection(
      id: _requiredString(json['id'], 'treatmentPlan.id'),
      medicationId: _requiredString(
        medicationJson['id'],
        'treatmentPlan.medication.id',
      ),
      medicationName: _requiredString(
        medicationJson['name'],
        'treatmentPlan.medication.name',
      ),
      strengthText: _optionalString(medicationJson['strengthText']),
      doseText: _requiredString(json['doseText'], 'treatmentPlan.doseText'),
      status: _requiredString(json['status'], 'treatmentPlan.status')
          .toLowerCase(),
      version: _positiveInt(json['version'], 'treatmentPlan.version'),
    );
  }

  final String id;
  final String medicationId;
  final String medicationName;
  final String? strengthText;
  final String doseText;
  final String status;
  final int version;
}

class CocoonPregnancyDoseOccurrenceProjection {
  const CocoonPregnancyDoseOccurrenceProjection({
    required this.id,
    required this.treatmentPlanId,
    required this.scheduledAtUtc,
    required this.scheduledLocalDate,
    required this.scheduledLocalTime,
    required this.timeZone,
    required this.status,
    required this.version,
  });

  factory CocoonPregnancyDoseOccurrenceProjection.fromJson(
    Map<String, dynamic> json,
  ) => CocoonPregnancyDoseOccurrenceProjection(
    id: _requiredString(json['id'], 'doseOccurrence.id'),
    treatmentPlanId: _requiredString(
      json['treatmentPlanId'],
      'doseOccurrence.treatmentPlanId',
    ),
    scheduledAtUtc: DateTime.parse(
      _requiredString(json['scheduledAtUtc'], 'doseOccurrence.scheduledAtUtc'),
    ).toUtc(),
    scheduledLocalDate: _requiredString(
      json['scheduledLocalDate'],
      'doseOccurrence.scheduledLocalDate',
    ),
    scheduledLocalTime: _requiredString(
      json['scheduledLocalTime'],
      'doseOccurrence.scheduledLocalTime',
    ),
    timeZone: _requiredString(json['timeZone'], 'doseOccurrence.timeZone'),
    status: _requiredString(json['status'], 'doseOccurrence.status')
        .toLowerCase(),
    version: _positiveInt(json['version'], 'doseOccurrence.version'),
  );

  /// Canonical dose-occurrence identity. Adherence mutations must target this
  /// value, never [treatmentPlanId] or a medication id.
  final String id;
  final String treatmentPlanId;
  final DateTime scheduledAtUtc;
  final String scheduledLocalDate;
  final String scheduledLocalTime;
  final String timeZone;
  final String status;
  final int version;
}

class CocoonPregnancyTreatmentContext {
  const CocoonPregnancyTreatmentContext({
    required this.contractVersion,
    required this.episodeId,
    required this.fromDate,
    required this.toDate,
    required this.treatmentPlans,
    required this.doseOccurrences,
    required this.typedTreatmentPlans,
    required this.typedDoseOccurrences,
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
        .map(
          (value) => Map<String, dynamic>.unmodifiable(
            Map<String, dynamic>.from(value),
          ),
        )
        .toList(growable: false);

    final rawPlans = objects(plans);
    final rawOccurrences = objects(occurrences);
    if (rawPlans.length != plans.length ||
        rawOccurrences.length != occurrences.length) {
      throw const FormatException(
        'Cocoon pregnancy treatment context contains non-object entries.',
      );
    }
    final typedPlans = rawPlans
        .map(CocoonPregnancyTreatmentPlanProjection.fromJson)
        .toList(growable: false);
    final typedOccurrences = rawOccurrences
        .map(CocoonPregnancyDoseOccurrenceProjection.fromJson)
        .toList(growable: false);
    final planIds = typedPlans.map((plan) => plan.id).toSet();
    if (typedOccurrences.any(
      (occurrence) => !planIds.contains(occurrence.treatmentPlanId),
    )) {
      throw const FormatException(
        'Cocoon pregnancy dose occurrence references an unknown treatment plan.',
      );
    }

    return CocoonPregnancyTreatmentContext(
      contractVersion: (json['contractVersion'] as num?)?.toInt() ?? 0,
      episodeId: episodeId,
      fromDate: fromDate,
      toDate: toDate,
      treatmentPlans: rawPlans,
      doseOccurrences: rawOccurrences,
      typedTreatmentPlans: typedPlans,
      typedDoseOccurrences: typedOccurrences,
      mutationAuthority: authority,
    );
  }

  final int contractVersion;
  final String episodeId;
  final String fromDate;
  final String toDate;

  /// Backward-compatible raw canonical payload for existing consumers.
  final List<Map<String, dynamic>> treatmentPlans;
  final List<Map<String, dynamic>> doseOccurrences;

  /// Typed read-only projections. These make treatment-plan identity and
  /// dose-occurrence identity explicit without creating a Cocoon mutation path.
  final List<CocoonPregnancyTreatmentPlanProjection> typedTreatmentPlans;
  final List<CocoonPregnancyDoseOccurrenceProjection> typedDoseOccurrences;
  final String mutationAuthority;
}

/// Read-only Cocoon projection over the canonical LifeMate treatment domain.
///
/// Mutations intentionally remain owned by the shared treatment APIs. Cocoon
/// must not create a second medication/treatment schedule or adherence path.
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
      response = await _http
          .get(
            uri,
            headers: {
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
            },
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

String _requiredString(Object? value, String field) {
  final normalized = value?.toString().trim() ?? '';
  if (normalized.isEmpty) {
    throw FormatException('Missing or invalid $field.');
  }
  return normalized;
}

String? _optionalString(Object? value) {
  final normalized = value?.toString().trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

int _positiveInt(Object? value, String field) {
  final parsed = value is num ? value.toInt() : int.tryParse('$value');
  if (parsed == null || parsed < 1) {
    throw FormatException('Missing or invalid $field.');
  }
  return parsed;
}
