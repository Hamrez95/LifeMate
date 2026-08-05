import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config.dart';
import 'lifemate_api_client.dart';

typedef LifeMateEditAccessTokenProvider = String? Function();

class LifeMateEditApi {
  LifeMateEditApi({
    required Uri baseUri,
    required LifeMateEditAccessTokenProvider accessToken,
    http.Client? httpClient,
  }) : _baseUri = baseUri,
       _accessToken = accessToken,
       _http = httpClient ?? http.Client();

  factory LifeMateEditApi.fromEnvironment({http.Client? httpClient}) {
    final config = AppConfig.fromEnvironment();
    return LifeMateEditApi(
      baseUri: config.apiBaseUri,
      accessToken: () =>
          Supabase.instance.client.auth.currentSession?.accessToken,
      httpClient: httpClient,
    );
  }

  final Uri _baseUri;
  final LifeMateEditAccessTokenProvider _accessToken;
  final http.Client _http;

  static const _timeout = Duration(seconds: 20);

  Future<Map<String, dynamic>> getCareEvent({
    required String eventId,
  }) async => _object(
    await _request('GET', '/api/v1/care-events/$eventId'),
  );

  Future<Map<String, dynamic>> updateTreatmentPlan({
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
    required String status,
  }) async => _object(
    await _request(
      'PATCH',
      '/api/v1/treatment-plans/$treatmentPlanId',
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

  Future<Map<String, dynamic>> updateCareEvent({
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
    required String status,
  }) async => _object(
    await _request(
      'PATCH',
      '/api/v1/care-events/$eventId',
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
        'status': status.trim().toLowerCase(),
      },
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
    } catch (error) {
      if (error is LifeMateApiException) rethrow;
      throw const LifeMateApiException(
        statusCode: 503,
        code: 'network_unavailable',
        message: 'The edit request could not reach LifeMate API.',
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
      message: problem['message']?.toString() ??
          problem['detail']?.toString() ??
          'LifeMate edit request failed.',
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

  static String? _emptyToNull(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
