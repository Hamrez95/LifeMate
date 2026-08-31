import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config.dart';
import 'lifemate_api_client.dart';

enum LifeMateSleepOptimizationMode {
  strictAnchorShift('strict_anchor_shift'),
  flexibleInterval('flexible_interval');

  const LifeMateSleepOptimizationMode(this.apiValue);
  final String apiValue;
}

class LifeMateSleepOptimizationOccurrence {
  const LifeMateSleepOptimizationOccurrence({
    required this.originalLocalDate,
    required this.originalLocalTime,
    required this.proposedLocalDate,
    required this.proposedLocalTime,
    required this.enteredGapMinutes,
    required this.proposedGapMinutes,
    required this.variationMinutes,
    required this.sleepHitBefore,
    required this.sleepHitAfter,
  });

  factory LifeMateSleepOptimizationOccurrence.fromJson(
    Map<String, dynamic> json,
  ) =>
      LifeMateSleepOptimizationOccurrence(
        originalLocalDate: json['originalLocalDate']?.toString() ?? '',
        originalLocalTime: json['originalLocalTime']?.toString() ?? '',
        proposedLocalDate: json['proposedLocalDate']?.toString() ?? '',
        proposedLocalTime: json['proposedLocalTime']?.toString() ?? '',
        enteredGapMinutes:
            int.tryParse(json['enteredGapMinutes']?.toString() ?? ''),
        proposedGapMinutes:
            int.tryParse(json['proposedGapMinutes']?.toString() ?? ''),
        variationMinutes:
            int.tryParse(json['variationMinutes']?.toString() ?? '') ?? 0,
        sleepHitBefore: json['sleepHitBefore'] == true,
        sleepHitAfter: json['sleepHitAfter'] == true,
      );

  final String originalLocalDate;
  final String originalLocalTime;
  final String proposedLocalDate;
  final String proposedLocalTime;
  final int? enteredGapMinutes;
  final int? proposedGapMinutes;
  final int variationMinutes;
  final bool sleepHitBefore;
  final bool sleepHitAfter;
}

class LifeMateSleepOptimizationPlanProposal {
  const LifeMateSleepOptimizationPlanProposal({
    required this.treatmentPlanId,
    required this.medicationName,
    required this.mode,
    required this.intervalHours,
    required this.oldAnchorLocalTime,
    required this.newAnchorLocalTime,
    required this.shiftMinutes,
    required this.sleepHitsBefore,
    required this.sleepHitsAfter,
    required this.maxVariationMinutes,
    required this.occurrences,
  });

  factory LifeMateSleepOptimizationPlanProposal.fromJson(
    Map<String, dynamic> json,
  ) =>
      LifeMateSleepOptimizationPlanProposal(
        treatmentPlanId: json['treatmentPlanId']?.toString() ?? '',
        medicationName: json['medicationName']?.toString() ?? '',
        mode: json['mode']?.toString() ?? '',
        intervalHours:
            int.tryParse(json['intervalHours']?.toString() ?? '') ?? 0,
        oldAnchorLocalTime: json['oldAnchorLocalTime']?.toString(),
        newAnchorLocalTime: json['newAnchorLocalTime']?.toString(),
        shiftMinutes: int.tryParse(json['shiftMinutes']?.toString() ?? '') ?? 0,
        sleepHitsBefore:
            int.tryParse(json['sleepHitsBefore']?.toString() ?? '') ?? 0,
        sleepHitsAfter:
            int.tryParse(json['sleepHitsAfter']?.toString() ?? '') ?? 0,
        maxVariationMinutes:
            int.tryParse(json['maxVariationMinutes']?.toString() ?? ''),
        occurrences:
            (json['occurrences'] is List ? json['occurrences'] as List : const [])
                .whereType<Map>()
                .map(
                  (item) => LifeMateSleepOptimizationOccurrence.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList(growable: false),
      );

  final String treatmentPlanId;
  final String medicationName;
  final String mode;
  final int intervalHours;
  final String? oldAnchorLocalTime;
  final String? newAnchorLocalTime;
  final int shiftMinutes;
  final int sleepHitsBefore;
  final int sleepHitsAfter;
  final int? maxVariationMinutes;
  final List<LifeMateSleepOptimizationOccurrence> occurrences;
}

class LifeMateSleepOptimizationPreview {
  const LifeMateSleepOptimizationPreview({
    required this.runId,
    required this.mode,
    required this.algorithmVersion,
    required this.consentTextVersion,
    required this.effectiveFromLocalDate,
    required this.effectiveUntilLocalDate,
    required this.maxVariationMinutes,
    required this.expiresAtUtc,
    required this.proposals,
    required this.exclusions,
  });

  factory LifeMateSleepOptimizationPreview.fromJson(Map<String, dynamic> json) =>
      LifeMateSleepOptimizationPreview(
        runId: json['runId']?.toString() ?? json['proposalId']?.toString() ?? '',
        mode: json['mode']?.toString() ?? '',
        algorithmVersion: json['algorithmVersion']?.toString() ?? '',
        consentTextVersion: json['consentTextVersion']?.toString() ?? '',
        effectiveFromLocalDate:
            json['effectiveFromLocalDate']?.toString() ?? '',
        effectiveUntilLocalDate:
            json['effectiveUntilLocalDate']?.toString() ?? '',
        maxVariationMinutes:
            int.tryParse(json['maxVariationMinutes']?.toString() ?? ''),
        expiresAtUtc: DateTime.tryParse(json['expiresAtUtc']?.toString() ?? ''),
        proposals:
            (json['proposals'] is List ? json['proposals'] as List : const [])
                .whereType<Map>()
                .map(
                  (item) => LifeMateSleepOptimizationPlanProposal.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList(growable: false),
        exclusions:
            (json['exclusions'] is List ? json['exclusions'] as List : const [])
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList(growable: false),
      );

  final String runId;
  final String mode;
  final String algorithmVersion;
  final String consentTextVersion;
  final String effectiveFromLocalDate;
  final String effectiveUntilLocalDate;
  final int? maxVariationMinutes;
  final DateTime? expiresAtUtc;
  final List<LifeMateSleepOptimizationPlanProposal> proposals;
  final List<Map<String, dynamic>> exclusions;

  bool get hasChanges => proposals.isNotEmpty;
}

class LifeMateSleepOptimizationReceipt {
  const LifeMateSleepOptimizationReceipt({
    required this.runId,
    required this.status,
    required this.mode,
    required this.effectiveFromLocalDate,
    required this.effectiveUntilLocalDate,
    required this.consentTextVersion,
  });

  factory LifeMateSleepOptimizationReceipt.fromJson(Map<String, dynamic> json) =>
      LifeMateSleepOptimizationReceipt(
        runId: json['runId']?.toString() ?? '',
        status: json['status']?.toString() ?? '',
        mode: json['mode']?.toString() ?? '',
        effectiveFromLocalDate:
            json['effectiveFromLocalDate']?.toString() ?? '',
        effectiveUntilLocalDate:
            json['effectiveUntilLocalDate']?.toString() ?? '',
        consentTextVersion: json['consentTextVersion']?.toString() ?? '',
      );

  final String runId;
  final String status;
  final String mode;
  final String effectiveFromLocalDate;
  final String effectiveUntilLocalDate;
  final String consentTextVersion;
}

typedef LifeMateMedicationSleepTokenProvider = String? Function();

class LifeMateMedicationSleepScheduleApi {
  LifeMateMedicationSleepScheduleApi({
    required Uri baseUri,
    required LifeMateMedicationSleepTokenProvider accessToken,
    http.Client? httpClient,
  })  : _baseUri = baseUri,
        _accessToken = accessToken,
        _http = httpClient ?? http.Client();

  factory LifeMateMedicationSleepScheduleApi.fromEnvironment({
    http.Client? httpClient,
  }) {
    final config = AppConfig.fromEnvironment();
    return LifeMateMedicationSleepScheduleApi(
      baseUri: config.apiBaseUri,
      accessToken: () =>
          Supabase.instance.client.auth.currentSession?.accessToken,
      httpClient: httpClient,
    );
  }

  final Uri _baseUri;
  final LifeMateMedicationSleepTokenProvider _accessToken;
  final http.Client _http;
  static const _timeout = Duration(seconds: 20);

  Future<LifeMateSleepOptimizationPreview> preview({
    required LifeMateSleepOptimizationMode mode,
    required DateTime effectiveFrom,
    required DateTime effectiveUntil,
    int? maxVariationMinutes,
  }) async =>
      LifeMateSleepOptimizationPreview.fromJson(
        await _post(
          '/api/v1/medication-schedule-optimizations/sleep/preview',
          {
            'mode': mode.apiValue,
            'effectiveFromLocalDate': _date(effectiveFrom),
            'effectiveUntilLocalDate': _date(effectiveUntil),
            if (mode == LifeMateSleepOptimizationMode.flexibleInterval)
              'maxVariationMinutes': maxVariationMinutes,
          },
        ),
      );

  Future<LifeMateSleepOptimizationReceipt> apply({
    required LifeMateSleepOptimizationPreview preview,
  }) async =>
      LifeMateSleepOptimizationReceipt.fromJson(
        await _post(
          '/api/v1/medication-schedule-optimizations/${preview.runId}/apply',
          {
            'mode': preview.mode,
            'acknowledgedTimingChanges': true,
          },
        ),
      );

  Future<void> undo(String runId) async {
    await _post(
      '/api/v1/medication-schedule-optimizations/$runId/undo',
      const <String, dynamic>{},
    );
  }

  Future<List<Map<String, dynamic>>> active() async {
    final response = await _get(
      '/api/v1/medication-schedule-optimizations/active',
    );
    final items = response['items'];
    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final response = await _send('GET', path, null);
    return _object(response);
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await _send('POST', path, body);
    return _object(response);
  }

  Future<dynamic> _send(
    String method,
    String path,
    Map<String, dynamic>? body,
  ) async {
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
      if (body != null)
        'Idempotency-Key': LifeMateApiClient.createClientRequestId(),
    };
    try {
      final response = method == 'GET'
          ? await _http.get(uri, headers: headers).timeout(_timeout)
          : await _http
              .post(uri, headers: headers, body: jsonEncode(body ?? const {}))
              .timeout(_timeout);
      final decoded =
          response.body.trim().isEmpty ? null : jsonDecode(response.body);
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
            'Medication schedule request failed.',
      );
    } on TimeoutException {
      throw const LifeMateApiException(
        statusCode: 0,
        code: 'network_timeout',
        message: 'Medication schedule request timed out.',
      );
    } on http.ClientException {
      throw const LifeMateApiException(
        statusCode: 0,
        code: 'network_unavailable',
        message: 'Medication schedule service is unavailable.',
      );
    }
  }

  static Map<String, dynamic> _object(dynamic value) {
    if (value is! Map) {
      throw const FormatException('Medication schedule response is invalid.');
    }
    return Map<String, dynamic>.from(value);
  }

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  void close() => _http.close();
}
