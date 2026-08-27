import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config.dart';
import 'lifemate_api_client.dart';

enum LifeMateFeedbackKind {
  feedback('Feedback'),
  nps('Nps'),
  bugReport('BugReport'),
  featureRequest('FeatureRequest'),
  advocacy('Advocacy');

  const LifeMateFeedbackKind(this.wireName);
  final String wireName;
}

class LifeMateFeedbackSubmission {
  const LifeMateFeedbackSubmission({
    required this.kind,
    required this.productCode,
    required this.idempotencyKey,
    this.appVersion,
    this.buildNumber,
    this.npsScore,
    this.message,
    this.advocacyOptIn = false,
  });

  final LifeMateFeedbackKind kind;
  final String productCode;
  final String idempotencyKey;
  final String? appVersion;
  final String? buildNumber;
  final int? npsScore;
  final String? message;
  final bool advocacyOptIn;

  Map<String, dynamic> toJson() => {
        'kind': kind.wireName,
        'productCode': productCode,
        if (appVersion != null) 'appVersion': appVersion,
        if (buildNumber != null) 'buildNumber': buildNumber,
        if (npsScore != null) 'npsScore': npsScore,
        if (message != null && message!.trim().isNotEmpty)
          'message': message!.trim(),
        if (kind == LifeMateFeedbackKind.advocacy)
          'advocacyOptIn': advocacyOptIn,
      };
}

typedef LifeMateFeedbackTokenProvider = String? Function();

class LifeMateFeedbackApi {
  LifeMateFeedbackApi({
    required Uri baseUri,
    required LifeMateFeedbackTokenProvider accessToken,
    http.Client? httpClient,
  })  : _baseUri = baseUri,
        _accessToken = accessToken,
        _http = httpClient ?? http.Client();

  factory LifeMateFeedbackApi.fromEnvironment({http.Client? httpClient}) {
    final config = AppConfig.fromEnvironment();
    return LifeMateFeedbackApi(
      baseUri: config.apiBaseUri,
      accessToken: () =>
          Supabase.instance.client.auth.currentSession?.accessToken,
      httpClient: httpClient,
    );
  }

  final Uri _baseUri;
  final LifeMateFeedbackTokenProvider _accessToken;
  final http.Client _http;
  static const _timeout = Duration(seconds: 20);

  Future<Map<String, dynamic>> submit(LifeMateFeedbackSubmission submission) async {
    final token = _accessToken();
    if (token == null || token.isEmpty) {
      throw const LifeMateApiException(
        statusCode: 401,
        code: 'session_missing',
        message: 'Authentication session is missing.',
      );
    }
    final key = submission.idempotencyKey.trim();
    if (key.isEmpty) {
      throw ArgumentError.value(submission.idempotencyKey, 'idempotencyKey');
    }
    final uri = _baseUri.replace(
      path: '${_baseUri.path.replaceFirst(RegExp(r'/$'), '')}/api/v1/feedback',
    );
    try {
      final response = await _http
          .post(
            uri,
            headers: {
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
              'Idempotency-Key': key,
            },
            body: jsonEncode(submission.toJson()),
          )
          .timeout(_timeout);
      final decoded = response.body.trim().isEmpty
          ? null
          : jsonDecode(response.body);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (decoded is! Map) {
          throw const FormatException('feedback_response_invalid');
        }
        return Map<String, dynamic>.from(decoded);
      }
      final problem = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : const <String, dynamic>{};
      throw LifeMateApiException(
        statusCode: response.statusCode,
        code: problem['code']?.toString() ?? 'feedback_request_failed',
        message: problem['detail']?.toString() ??
            problem['message']?.toString() ??
            'Feedback request failed.',
      );
    } on TimeoutException {
      throw const LifeMateApiException(
        statusCode: 0,
        code: 'network_timeout',
        message: 'Feedback request timed out.',
      );
    } on http.ClientException {
      throw const LifeMateApiException(
        statusCode: 0,
        code: 'network_unavailable',
        message: 'Feedback service is unavailable.',
      );
    }
  }

  void close() => _http.close();
}

String lifeMateFeedbackRequestId() => LifeMateApiClient.createClientRequestId();
