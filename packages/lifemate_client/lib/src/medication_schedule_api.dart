import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config.dart';
import 'lifemate_api_client.dart';

class LifeMateMedicationSchedulePreferences {
  const LifeMateMedicationSchedulePreferences({
    required this.timeZone,
    required this.sleepWindowEnabled,
    required this.sleepStartLocalTime,
    required this.sleepEndLocalTime,
    required this.version,
  });

  factory LifeMateMedicationSchedulePreferences.fromJson(
    Map<String, dynamic> json,
  ) =>
      LifeMateMedicationSchedulePreferences(
        timeZone: json['timeZone']?.toString() ?? '',
        sleepWindowEnabled: json['sleepWindowEnabled'] == true,
        sleepStartLocalTime: _nullable(json['sleepStartLocalTime']),
        sleepEndLocalTime: _nullable(json['sleepEndLocalTime']),
        version: int.tryParse(json['version']?.toString() ?? '') ?? 0,
      );

  final String timeZone;
  final bool sleepWindowEnabled;
  final String? sleepStartLocalTime;
  final String? sleepEndLocalTime;
  final int version;

  static String? _nullable(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}

class LifeMateTreatmentPlanTiming {
  const LifeMateTreatmentPlanTiming({
    required this.treatmentPlanId,
    required this.treatmentPlanVersion,
    required this.nearbyGroupingEnabled,
    required this.timingLocked,
    required this.manualSpacingBeforeMinutes,
    required this.manualSpacingAfterMinutes,
    required this.timingNote,
    required this.version,
  });

  factory LifeMateTreatmentPlanTiming.fromJson(Map<String, dynamic> json) =>
      LifeMateTreatmentPlanTiming(
        treatmentPlanId: json['treatmentPlanId']?.toString() ?? '',
        treatmentPlanVersion:
            int.tryParse(json['treatmentPlanVersion']?.toString() ?? '') ?? 0,
        nearbyGroupingEnabled: json['nearbyGroupingEnabled'] == true,
        timingLocked: json['timingLocked'] == true,
        manualSpacingBeforeMinutes:
            int.tryParse(json['manualSpacingBeforeMinutes']?.toString() ?? '') ??
                0,
        manualSpacingAfterMinutes:
            int.tryParse(json['manualSpacingAfterMinutes']?.toString() ?? '') ??
                0,
        timingNote:
            LifeMateMedicationSchedulePreferences._nullable(json['timingNote']),
        version: int.tryParse(json['version']?.toString() ?? '') ?? 0,
      );

  final String treatmentPlanId;
  final int treatmentPlanVersion;
  final bool nearbyGroupingEnabled;
  final bool timingLocked;
  final int manualSpacingBeforeMinutes;
  final int manualSpacingAfterMinutes;
  final String? timingNote;
  final int version;
}

class LifeMateMedicationSchedulePlan {
  const LifeMateMedicationSchedulePlan({
    required this.medicationName,
    required this.strengthText,
    required this.recurrence,
    required this.recurrenceStartLocalTime,
    required this.timing,
  });

  factory LifeMateMedicationSchedulePlan.fromJson(Map<String, dynamic> json) =>
      LifeMateMedicationSchedulePlan(
        medicationName: json['medicationName']?.toString() ?? '',
        strengthText:
            LifeMateMedicationSchedulePreferences._nullable(json['strengthText']),
        recurrence: json['recurrence'] is Map
            ? Map<String, dynamic>.from(json['recurrence'] as Map)
            : null,
        recurrenceStartLocalTime:
            LifeMateMedicationSchedulePreferences._nullable(
          json['recurrenceStartLocalTime'],
        ),
        timing: LifeMateTreatmentPlanTiming.fromJson(json),
      );

  final String medicationName;
  final String? strengthText;
  final Map<String, dynamic>? recurrence;
  final String? recurrenceStartLocalTime;
  final LifeMateTreatmentPlanTiming timing;
}

class LifeMateNearbyDoseChange {
  const LifeMateNearbyDoseChange({
    required this.treatmentPlanId,
    required this.medicationName,
    required this.oldAnchorLocalTime,
    required this.newAnchorLocalTime,
    required this.intervalHoursBefore,
    required this.intervalHoursAfter,
    required this.shiftMinutes,
  });

  factory LifeMateNearbyDoseChange.fromJson(Map<String, dynamic> json) =>
      LifeMateNearbyDoseChange(
        treatmentPlanId: json['treatmentPlanId']?.toString() ?? '',
        medicationName: json['medicationName']?.toString() ?? '',
        oldAnchorLocalTime: json['oldAnchorLocalTime']?.toString() ?? '',
        newAnchorLocalTime: json['newAnchorLocalTime']?.toString() ?? '',
        intervalHoursBefore:
            int.tryParse(json['intervalHoursBefore']?.toString() ?? '') ?? 0,
        intervalHoursAfter:
            int.tryParse(json['intervalHoursAfter']?.toString() ?? '') ?? 0,
        shiftMinutes: int.tryParse(json['shiftMinutes']?.toString() ?? '') ?? 0,
      );

  final String treatmentPlanId;
  final String medicationName;
  final String oldAnchorLocalTime;
  final String newAnchorLocalTime;
  final int intervalHoursBefore;
  final int intervalHoursAfter;
  final int shiftMinutes;
}

class LifeMateNearbyDoseGroup {
  const LifeMateNearbyDoseGroup({
    required this.sharedLocalTime,
    required this.changes,
  });

  factory LifeMateNearbyDoseGroup.fromJson(Map<String, dynamic> json) =>
      LifeMateNearbyDoseGroup(
        sharedLocalTime: json['sharedLocalTime']?.toString() ?? '',
        changes: (json['changes'] is List ? json['changes'] as List : const [])
            .whereType<Map>()
            .map(
              (item) => LifeMateNearbyDoseChange.fromJson(
                Map<String, dynamic>.from(item),
              ),
            )
            .toList(growable: false),
      );

  final String sharedLocalTime;
  final List<LifeMateNearbyDoseChange> changes;
}

class LifeMateNearbyDoseExclusion {
  const LifeMateNearbyDoseExclusion({
    required this.treatmentPlanId,
    required this.medicationName,
    required this.reason,
  });

  factory LifeMateNearbyDoseExclusion.fromJson(Map<String, dynamic> json) =>
      LifeMateNearbyDoseExclusion(
        treatmentPlanId: json['treatmentPlanId']?.toString() ?? '',
        medicationName: json['medicationName']?.toString() ?? '',
        reason: json['reason']?.toString() ?? '',
      );

  final String treatmentPlanId;
  final String medicationName;
  final String reason;
}

class LifeMateNearbyDoseProposal {
  const LifeMateNearbyDoseProposal({
    required this.proposalId,
    required this.expiresAtUtc,
    required this.algorithmVersion,
    required this.groups,
    required this.exclusions,
    required this.expectedNotificationReduction,
  });

  factory LifeMateNearbyDoseProposal.fromJson(Map<String, dynamic> json) =>
      LifeMateNearbyDoseProposal(
        proposalId: json['proposalId']?.toString() ?? '',
        expiresAtUtc: DateTime.tryParse(json['expiresAtUtc']?.toString() ?? ''),
        algorithmVersion: json['algorithmVersion']?.toString() ?? '',
        groups: (json['groups'] is List ? json['groups'] as List : const [])
            .whereType<Map>()
            .map(
              (item) => LifeMateNearbyDoseGroup.fromJson(
                Map<String, dynamic>.from(item),
              ),
            )
            .toList(growable: false),
        exclusions:
            (json['exclusions'] is List ? json['exclusions'] as List : const [])
                .whereType<Map>()
                .map(
                  (item) => LifeMateNearbyDoseExclusion.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList(growable: false),
        expectedNotificationReduction: int.tryParse(
              json['expectedNotificationReduction']?.toString() ?? '',
            ) ??
            0,
      );

  final String proposalId;
  final DateTime? expiresAtUtc;
  final String algorithmVersion;
  final List<LifeMateNearbyDoseGroup> groups;
  final List<LifeMateNearbyDoseExclusion> exclusions;
  final int expectedNotificationReduction;

  bool get hasChanges => groups.any((group) => group.changes.isNotEmpty);
}

class LifeMateNearbyDoseApplyResult {
  const LifeMateNearbyDoseApplyResult({
    required this.proposalId,
    required this.status,
    required this.alreadyApplied,
  });

  factory LifeMateNearbyDoseApplyResult.fromJson(Map<String, dynamic> json) =>
      LifeMateNearbyDoseApplyResult(
        proposalId: json['proposalId']?.toString() ?? '',
        status: json['status']?.toString() ?? '',
        alreadyApplied: json['alreadyApplied'] == true,
      );

  final String proposalId;
  final String status;
  final bool alreadyApplied;
}

typedef LifeMateMedicationScheduleTokenProvider = String? Function();

class LifeMateMedicationScheduleApi {
  LifeMateMedicationScheduleApi({
    required Uri baseUri,
    required LifeMateMedicationScheduleTokenProvider accessToken,
    http.Client? httpClient,
  })  : _baseUri = baseUri,
        _accessToken = accessToken,
        _http = httpClient ?? http.Client();

  factory LifeMateMedicationScheduleApi.fromEnvironment({
    http.Client? httpClient,
  }) {
    final config = AppConfig.fromEnvironment();
    return LifeMateMedicationScheduleApi(
      baseUri: config.apiBaseUri,
      accessToken: () =>
          Supabase.instance.client.auth.currentSession?.accessToken,
      httpClient: httpClient,
    );
  }

  final Uri _baseUri;
  final LifeMateMedicationScheduleTokenProvider _accessToken;
  final http.Client _http;
  static const _timeout = Duration(seconds: 20);

  Future<LifeMateMedicationSchedulePreferences> getPreferences() async =>
      LifeMateMedicationSchedulePreferences.fromJson(
        _object(
          await _request('GET', '/api/v1/medication-schedule/preferences'),
        ),
      );

  Future<List<LifeMateMedicationSchedulePlan>> listPlans() async {
    final response = _object(
      await _request('GET', '/api/v1/medication-schedule/plans'),
    );
    final items = response['items'];
    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map(
          (item) => LifeMateMedicationSchedulePlan.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .toList(growable: false);
  }

  Future<LifeMateNearbyDoseProposal> previewNearbyDoseOptimization() async =>
      LifeMateNearbyDoseProposal.fromJson(
        _object(
          await _request(
            'POST',
            '/api/v1/medication-schedule-optimizations/nearby/preview',
            body: const <String, dynamic>{},
          ),
        ),
      );

  Future<LifeMateNearbyDoseApplyResult> applyNearbyDoseOptimization(
    String proposalId,
  ) async =>
      LifeMateNearbyDoseApplyResult.fromJson(
        _object(
          await _request(
            'POST',
            '/api/v1/medication-schedule-optimizations/$proposalId/apply',
            body: const <String, dynamic>{'confirmed': true},
          ),
        ),
      );

  Future<LifeMateMedicationSchedulePreferences> savePreferences({
    required LifeMateMedicationSchedulePreferences current,
    required String timeZone,
    required bool sleepWindowEnabled,
    String? sleepStartLocalTime,
    String? sleepEndLocalTime,
  }) async =>
      LifeMateMedicationSchedulePreferences.fromJson(
        _object(
          await _request(
            'PATCH',
            '/api/v1/medication-schedule/preferences',
            body: {
              'version': current.version,
              'timeZone': timeZone,
              'sleepWindowEnabled': sleepWindowEnabled,
              'sleepStartLocalTime':
                  sleepWindowEnabled ? sleepStartLocalTime : null,
              'sleepEndLocalTime':
                  sleepWindowEnabled ? sleepEndLocalTime : null,
            },
          ),
        ),
      );

  Future<LifeMateTreatmentPlanTiming> getPlanTiming(
    String treatmentPlanId,
  ) async =>
      LifeMateTreatmentPlanTiming.fromJson(
        _object(
          await _request(
            'GET',
            '/api/v1/treatment-plans/$treatmentPlanId/timing',
          ),
        ),
      );

  Future<LifeMateTreatmentPlanTiming> savePlanTiming({
    required LifeMateTreatmentPlanTiming current,
    required bool nearbyGroupingEnabled,
    required bool timingLocked,
    required int manualSpacingBeforeMinutes,
    required int manualSpacingAfterMinutes,
    String? timingNote,
  }) async =>
      LifeMateTreatmentPlanTiming.fromJson(
        _object(
          await _request(
            'PATCH',
            '/api/v1/treatment-plans/${current.treatmentPlanId}/timing',
            body: {
              'version': current.version,
              'treatmentPlanVersion': current.treatmentPlanVersion,
              'nearbyGroupingEnabled': nearbyGroupingEnabled,
              'timingLocked': timingLocked,
              'manualSpacingBeforeMinutes': manualSpacingBeforeMinutes,
              'manualSpacingAfterMinutes': manualSpacingAfterMinutes,
              'timingNote': timingNote,
            },
          ),
        ),
      );

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
      if (body != null)
        'Idempotency-Key': LifeMateApiClient.createClientRequestId(),
    };
    try {
      final response = switch (method) {
        'GET' => await _http.get(uri, headers: headers).timeout(_timeout),
        'POST' => await _http
            .post(uri, headers: headers, body: jsonEncode(body ?? const {}))
            .timeout(_timeout),
        'PATCH' => await _http
            .patch(uri, headers: headers, body: jsonEncode(body))
            .timeout(_timeout),
        _ => throw ArgumentError.value(method, 'method'),
      };
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

  void close() => _http.close();
}
