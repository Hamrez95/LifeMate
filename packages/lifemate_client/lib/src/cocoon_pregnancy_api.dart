import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'cocoon_pregnancy.dart';
import 'lifemate_api_client.dart'
    show AccessTokenProvider, LifeMateApiException;

class CocoonPregnancyApiClient {
  CocoonPregnancyApiClient({
    required Uri baseUri,
    required AccessTokenProvider accessToken,
    http.Client? httpClient,
  })  : _baseUri = baseUri,
        _accessToken = accessToken,
        _http = httpClient ?? http.Client();

  final Uri _baseUri;
  final AccessTokenProvider _accessToken;
  final http.Client _http;
  static const _timeout = Duration(seconds: 20);

  Future<CocoonBootstrapSnapshot> bootstrap(
          {required DateTime asOfDate}) async =>
      CocoonBootstrapSnapshot.fromJson(
        await _object(
          'GET',
          '/api/v1/cocoon/bootstrap',
          query: {'asOfDate': _date(asOfDate)},
        ),
      );

  Future<CocoonPregnancySnapshot> getSnapshot({
    required DateTime asOfDate,
  }) async =>
      CocoonPregnancySnapshot.fromJson(
        await _object(
          'GET',
          '/api/v1/cocoon/pregnancy/snapshot',
          query: {'asOfDate': _date(asOfDate)},
        ),
      );

  Future<List<CocoonPregnancyEpisode>> listEpisodes(
      {DateTime? asOfDate}) async {
    final value = await _object(
      'GET',
      '/api/v1/cocoon/pregnancy/episodes',
      query: asOfDate == null ? null : {'asOfDate': _date(asOfDate)},
    );
    final episodes = value['episodes'];
    if (episodes is! List) return const [];
    return episodes
        .whereType<Map<String, dynamic>>()
        .map(CocoonPregnancyEpisode.fromJson)
        .toList(growable: false);
  }

  Future<CocoonPregnancyEpisode> createEpisode({
    required String idempotencyKey,
    required String status,
    String? method,
    String? lmpDate,
    String? estimatedDueDate,
    String? referenceDate,
    int? gestationalAgeAtReferenceDays,
  }) async =>
      _episodeFromEnvelope(
        await _object(
          'POST',
          '/api/v1/cocoon/pregnancy/episodes',
          idempotencyKey: idempotencyKey,
          body: {
            'status': status,
            'method': method,
            'lmpDate': lmpDate,
            'estimatedDueDate': estimatedDueDate,
            'referenceDate': referenceDate,
            'gestationalAgeAtReferenceDays': gestationalAgeAtReferenceDays,
          },
        ),
      );

  Future<CocoonPregnancyEpisode> activateEpisode({
    required String episodeId,
    required int expectedVersion,
    required String idempotencyKey,
  }) async =>
      _episodeFromEnvelope(
        await _object(
          'POST',
          '/api/v1/cocoon/pregnancy/episodes/$episodeId/activate',
          idempotencyKey: idempotencyKey,
          body: {'expectedVersion': expectedVersion},
        ),
      );

  Future<CocoonPregnancyEpisode> reviseDating({
    required String episodeId,
    required int expectedVersion,
    required String method,
    required String source,
    required String idempotencyKey,
    String? lmpDate,
    String? estimatedDueDate,
    String? referenceDate,
    int? gestationalAgeAtReferenceDays,
    String? reasonCode,
  }) async =>
      _episodeFromEnvelope(
        await _object(
          'PATCH',
          '/api/v1/cocoon/pregnancy/episodes/$episodeId/dating',
          idempotencyKey: idempotencyKey,
          body: {
            'expectedVersion': expectedVersion,
            'method': method,
            'source': source,
            'lmpDate': lmpDate,
            'estimatedDueDate': estimatedDueDate,
            'referenceDate': referenceDate,
            'gestationalAgeAtReferenceDays': gestationalAgeAtReferenceDays,
            'reasonCode': reasonCode,
          },
        ),
      );

  Future<CocoonPregnancyEpisode> endEpisode({
    required String episodeId,
    required int expectedVersion,
    required String outcome,
    required String idempotencyKey,
  }) async =>
      _episodeFromEnvelope(
        await _object(
          'POST',
          '/api/v1/cocoon/pregnancy/episodes/$episodeId/end',
          idempotencyKey: idempotencyKey,
          body: {'expectedVersion': expectedVersion, 'outcome': outcome},
        ),
      );

  CocoonPregnancyEpisode _episodeFromEnvelope(Map<String, dynamic> value) {
    final episode = value['episode'];
    if (episode is! Map<String, dynamic>) {
      throw const FormatException('Cocoon pregnancy episode is missing.');
    }
    return CocoonPregnancyEpisode.fromJson(episode);
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
      final encoded = body == null ? null : jsonEncode(body);
      response = switch (method) {
        'GET' => await _http.get(uri, headers: headers).timeout(_timeout),
        'POST' => await _http
            .post(uri, headers: headers, body: encoded)
            .timeout(_timeout),
        'PATCH' => await _http
            .patch(uri, headers: headers, body: encoded)
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
      throw const FormatException(
          'LifeMate API returned a non-object payload.');
    }
    return decoded;
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
