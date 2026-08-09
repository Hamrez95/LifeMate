import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config.dart';
import 'lifemate_api_client.dart';
import 'reminder_lead_time.dart';

typedef LifeMateCareManagementAccessTokenProvider = String? Function();

class LifeMateCareManagementApi {
  LifeMateCareManagementApi({
    required Uri baseUri,
    required LifeMateCareManagementAccessTokenProvider accessToken,
    http.Client? httpClient,
  }) : _baseUri = baseUri,
       _accessToken = accessToken,
       _http = httpClient ?? http.Client();

  factory LifeMateCareManagementApi.fromEnvironment({http.Client? httpClient}) {
    final config = AppConfig.fromEnvironment();
    return LifeMateCareManagementApi(
      baseUri: managementBaseUriFor(config.apiBaseUri),
      accessToken: () =>
          Supabase.instance.client.auth.currentSession?.accessToken,
      httpClient: httpClient,
    );
  }

  final Uri _baseUri;
  final LifeMateCareManagementAccessTokenProvider _accessToken;
  final http.Client _http;

  /// Resolves the dedicated care-management function beside the configured
  /// API function while preserving environment suffixes such as `-candidate`.
  static Uri managementBaseUriFor(Uri apiBase) {
    final segments = apiBase.pathSegments.toList(growable: true);
    if (segments.isEmpty) {
      segments.add('lifemate-care-management');
    } else {
      final last = segments.last;
      if (last == 'lifemate-api') {
        segments[segments.length - 1] = 'lifemate-care-management';
      } else if (last.startsWith('lifemate-api-')) {
        final suffix = last.substring('lifemate-api'.length);
        segments[segments.length - 1] = 'lifemate-care-management$suffix';
      } else if (!last.startsWith('lifemate-care-management')) {
        segments.add('lifemate-care-management');
      }
    }
    return apiBase.replace(path: '/${segments.join('/')}');
  }

  static const _timeout = Duration(seconds: 20);

  Future<Map<String, dynamic>> getRelationshipPermission({
    required String relationshipId,
  }) async => _object(
    await _request(
      'GET',
      '/api/v1/relationships/$relationshipId/health-record-permission',
    ),
  );

  Future<Map<String, dynamic>> updateHealthRecordPermission({
    required String relationshipId,
    required bool enabled,
    bool confirmConsent = false,
  }) async => _object(
    await _request(
      'PATCH',
      '/api/v1/relationships/$relationshipId/health-record-permission',
      body: {
        'canManageHealthRecord': enabled,
        if (enabled) ...{
          'confirmConsent': confirmConsent,
          'consentVersion': 'health-record-management-consent-v1',
        },
      },
    ),
  );

  Future<List<Map<String, dynamic>>> getTreatmentPlans({
    required String patientUserId,
  }) async => _list(
    await _request('GET', '/api/v1/patients/$patientUserId/treatment-plans'),
  );

  Future<Map<String, dynamic>> createTreatmentPlan({
    required String patientUserId,
    required String medicationName,
    String? strengthText,
    String? form,
    required String doseText,
    String? instructions,
    required DateTime startDate,
    DateTime? endDate,
    required String timeZone,
    required List<Map<String, String>> schedules,
    int patientReminderMinutesBefore =
        LifeMateReminderLeadTimes.defaultPatientMinutes,
    int caregiverReminderMinutesBefore =
        LifeMateReminderLeadTimes.defaultCaregiverMinutes,
  }) async => _object(
    await _request(
      'POST',
      '/api/v1/patients/$patientUserId/treatment-plans',
      body: {
        'medicationName': medicationName.trim(),
        'strengthText': _emptyToNull(strengthText),
        'form': _emptyToNull(form),
        'doseText': doseText.trim(),
        'instructions': _emptyToNull(instructions),
        'startDate': _date(startDate),
        'endDate': endDate == null ? null : _date(endDate),
        'timeZone': timeZone.trim(),
        'schedules': schedules,
        'patientReminderMinutesBefore': patientReminderMinutesBefore,
        'caregiverReminderMinutesBefore': caregiverReminderMinutesBefore,
      },
    ),
  );

  Future<Map<String, dynamic>> updateTreatmentPlan({
    required String patientUserId,
    required String treatmentPlanId,
    required int version,
    required int medicationVersion,
    required String medicationName,
    String? strengthText,
    String? form,
    required String doseText,
    String? instructions,
    required DateTime startDate,
    DateTime? endDate,
    required String timeZone,
    required List<Map<String, String>> schedules,
    required int patientReminderMinutesBefore,
    required int caregiverReminderMinutesBefore,
    String status = 'active',
  }) async => _object(
    await _request(
      'PATCH',
      '/api/v1/patients/$patientUserId/treatment-plans/$treatmentPlanId',
      body: {
        'version': version,
        'medicationVersion': medicationVersion,
        'medicationName': medicationName.trim(),
        'strengthText': _emptyToNull(strengthText),
        'form': _emptyToNull(form),
        'doseText': doseText.trim(),
        'instructions': _emptyToNull(instructions),
        'startDate': _date(startDate),
        'endDate': endDate == null ? null : _date(endDate),
        'timeZone': timeZone.trim(),
        'schedules': schedules,
        'patientReminderMinutesBefore': patientReminderMinutesBefore,
        'caregiverReminderMinutesBefore': caregiverReminderMinutesBefore,
        'status': status.trim().toLowerCase(),
      },
    ),
  );

  Future<void> deleteTreatmentPlan({
    required String patientUserId,
    required String treatmentPlanId,
    required int version,
  }) async {
    await _request(
      'DELETE',
      '/api/v1/patients/$patientUserId/treatment-plans/$treatmentPlanId',
      body: {'version': version},
    );
  }

  Future<List<Map<String, dynamic>>> getCareEvents({
    required String patientUserId,
  }) async => _list(
    await _request('GET', '/api/v1/patients/$patientUserId/care-events'),
  );

  Future<Map<String, dynamic>> createCareEvent({
    required String patientUserId,
    required String clientRequestId,
    required String eventType,
    required String title,
    required DateTime scheduledLocalDate,
    required String scheduledLocalTime,
    required String timeZone,
    String? providerName,
    String? specialty,
    String? medicationName,
    String? doseText,
    String? administrationRoute,
    String? reason,
    String? instructions,
    String? centerName,
    String? addressLine,
    String? phoneNumber,
    int patientReminderMinutesBefore =
        LifeMateReminderLeadTimes.defaultPatientMinutes,
    int caregiverReminderMinutesBefore =
        LifeMateReminderLeadTimes.defaultCaregiverMinutes,
  }) async => _object(
    await _request(
      'POST',
      '/api/v1/patients/$patientUserId/care-events',
      body: {
        'clientRequestId': clientRequestId,
        'eventType': eventType.trim().toLowerCase(),
        'title': title.trim(),
        'providerName': _emptyToNull(providerName),
        'specialty': _emptyToNull(specialty),
        'medicationName': _emptyToNull(medicationName),
        'doseText': _emptyToNull(doseText),
        'administrationRoute': _emptyToNull(administrationRoute),
        'reason': _emptyToNull(reason),
        'instructions': _emptyToNull(instructions),
        'centerName': _emptyToNull(centerName),
        'addressLine': _emptyToNull(addressLine),
        'phoneNumber': _emptyToNull(phoneNumber),
        'scheduledLocalDate': _date(scheduledLocalDate),
        'scheduledLocalTime': scheduledLocalTime.trim(),
        'timeZone': timeZone.trim(),
        'patientReminderMinutesBefore': patientReminderMinutesBefore,
        'caregiverReminderMinutesBefore': caregiverReminderMinutesBefore,
      },
    ),
  );

  Future<Map<String, dynamic>> updateCareEvent({
    required String patientUserId,
    required String eventId,
    required int version,
    required String eventType,
    required String title,
    required DateTime scheduledLocalDate,
    required String scheduledLocalTime,
    required String timeZone,
    String? providerName,
    String? specialty,
    String? medicationName,
    String? doseText,
    String? administrationRoute,
    String? reason,
    String? instructions,
    String? centerName,
    String? addressLine,
    String? phoneNumber,
    required int patientReminderMinutesBefore,
    required int caregiverReminderMinutesBefore,
  }) async => _object(
    await _request(
      'PATCH',
      '/api/v1/patients/$patientUserId/care-events/$eventId',
      body: {
        'version': version,
        'eventType': eventType.trim().toLowerCase(),
        'title': title.trim(),
        'providerName': _emptyToNull(providerName),
        'specialty': _emptyToNull(specialty),
        'medicationName': _emptyToNull(medicationName),
        'doseText': _emptyToNull(doseText),
        'administrationRoute': _emptyToNull(administrationRoute),
        'reason': _emptyToNull(reason),
        'instructions': _emptyToNull(instructions),
        'centerName': _emptyToNull(centerName),
        'addressLine': _emptyToNull(addressLine),
        'phoneNumber': _emptyToNull(phoneNumber),
        'scheduledLocalDate': _date(scheduledLocalDate),
        'scheduledLocalTime': scheduledLocalTime.trim(),
        'timeZone': timeZone.trim(),
        'patientReminderMinutesBefore': patientReminderMinutesBefore,
        'caregiverReminderMinutesBefore': caregiverReminderMinutesBefore,
      },
    ),
  );

  Future<void> deleteCareEvent({
    required String patientUserId,
    required String eventId,
    required int version,
  }) async {
    await _request(
      'DELETE',
      '/api/v1/patients/$patientUserId/care-events/$eventId',
      body: {'version': version},
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
    final uri = _resolve(path);
    final headers = <String, String>{
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
      if (body != null) 'Content-Type': 'application/json',
    };
    final encodedBody = body == null ? null : jsonEncode(body);

    late final http.Response response;
    try {
      response = switch (method) {
        'GET' => await _http.get(uri, headers: headers).timeout(_timeout),
        'POST' =>
          await _http
              .post(uri, headers: headers, body: encodedBody)
              .timeout(_timeout),
        'PATCH' =>
          await _http
              .patch(uri, headers: headers, body: encodedBody)
              .timeout(_timeout),
        'DELETE' =>
          await _http
              .delete(uri, headers: headers, body: encodedBody)
              .timeout(_timeout),
        _ => throw ArgumentError.value(method, 'method'),
      };
    } on TimeoutException {
      throw const LifeMateApiException(
        statusCode: 0,
        code: 'network_timeout',
        message: 'LifeMate care management request timed out.',
      );
    } on http.ClientException {
      throw const LifeMateApiException(
        statusCode: 0,
        code: 'network_unavailable',
        message: 'LifeMate care management service is unavailable.',
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
      message:
          problem['message']?.toString() ??
          problem['detail']?.toString() ??
          'LifeMate care management request failed.',
    );
  }

  Uri _resolve(String path) {
    final basePath = _baseUri.path.replaceFirst(RegExp(r'/$'), '');
    return _baseUri.replace(path: '$basePath$path');
  }

  static Map<String, dynamic> _object(dynamic value) {
    if (value is! Map) {
      throw const FormatException(
        'LifeMate care management API returned a non-object payload.',
      );
    }
    return Map<String, dynamic>.from(value);
  }

  static List<Map<String, dynamic>> _list(dynamic value) {
    if (value is! List) {
      throw const FormatException(
        'LifeMate care management API returned a non-list payload.',
      );
    }
    return value
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList(growable: false);
  }

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static String? _emptyToNull(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
