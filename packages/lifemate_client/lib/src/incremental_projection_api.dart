import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:lifemate_core/lifemate_core.dart';

import 'lifemate_api_client.dart';

/// Authenticated owner-only incremental projection transport for the shared
/// offline runtime. Health rows never bypass lifemate-api and the cursor remains
/// opaque to callers.
final class LifeMateIncrementalProjectionApi {
  LifeMateIncrementalProjectionApi({
    required Uri baseUri,
    required AccessTokenProvider accessToken,
    http.Client? httpClient,
  }) : _baseUri = baseUri,
       _accessToken = accessToken,
       _http = httpClient ?? http.Client();

  final Uri _baseUri;
  final AccessTokenProvider _accessToken;
  final http.Client _http;

  Future<LifeMateProjectionPullPage> pullCareEvents({
    String? cursor,
    int limit = 100,
  }) async {
    if (limit < 1 || limit > 200) {
      throw ArgumentError.value(limit, 'limit', 'Must be between 1 and 200.');
    }
    final token = _accessToken()?.trim();
    if (token == null || token.isEmpty) {
      throw const LifeMateApiException(
        statusCode: 401,
        code: 'authorization_missing',
        message: 'Authentication is required.',
      );
    }
    final query = <String, String>{'limit': '$limit'};
    final normalizedCursor = cursor?.trim();
    if (normalizedCursor != null && normalizedCursor.isNotEmpty) {
      query['cursor'] = normalizedCursor;
    }
    final uri = _baseUri.resolve('/api/v1/sync/care-events').replace(
      queryParameters: query,
    );
    final response = await _http
        .get(
          uri,
          headers: <String, String>{
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
          },
        )
        .timeout(const Duration(seconds: 20));
    final decoded = _decodeResponse(response);
    return _parsePage(decoded);
  }

  void close() => _http.close();

  static Map<String, dynamic> _decodeResponse(http.Response response) {
    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      decoded = null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final problem = decoded is Map<String, dynamic> ? decoded : const {};
      throw LifeMateApiException(
        statusCode: response.statusCode,
        code: _requiredString(problem['code'], fallback: 'request_failed'),
        message: _requiredString(
          problem['message'] ?? problem['detail'],
          fallback: 'The request could not be completed.',
        ),
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const LifeMateApiException(
        statusCode: 502,
        code: 'invalid_api_response',
        message: 'The service returned an invalid response.',
      );
    }
    return decoded;
  }

  static LifeMateProjectionPullPage _parsePage(Map<String, dynamic> json) {
    final nextCursor = _requiredString(json['nextCursor']);
    final hasMore = json['hasMore'];
    final rawChanges = json['changes'];
    if (hasMore is! bool || rawChanges is! List) {
      throw const LifeMateApiException(
        statusCode: 502,
        code: 'invalid_api_response',
        message: 'The service returned an invalid sync page.',
      );
    }
    final changes = <LifeMateServerProjectionChange>[];
    for (final raw in rawChanges) {
      if (raw is! Map) {
        throw const LifeMateApiException(
          statusCode: 502,
          code: 'invalid_api_response',
          message: 'The service returned an invalid sync change.',
        );
      }
      final value = Map<String, dynamic>.from(raw);
      final recordKey = _requiredString(value['recordKey']);
      final sourceRevision = _optionalString(value['sourceRevision']);
      final sourceUpdatedAtUtc = _optionalDate(value['sourceUpdatedAtUtc']);
      if (value['deleted'] == true) {
        changes.add(
          LifeMateServerProjectionChange.delete(
            recordKey: recordKey,
            sourceRevision: sourceRevision,
            sourceUpdatedAtUtc: sourceUpdatedAtUtc,
          ),
        );
        continue;
      }
      final payload = value['payload'];
      if (payload is! Map) {
        throw const LifeMateApiException(
          statusCode: 502,
          code: 'invalid_api_response',
          message: 'The service returned an invalid sync payload.',
        );
      }
      changes.add(
        LifeMateServerProjectionChange.upsert(
          recordKey: recordKey,
          payload: Map<String, dynamic>.from(payload),
          sourceRevision: sourceRevision,
          sourceUpdatedAtUtc: sourceUpdatedAtUtc,
        ),
      );
    }
    return LifeMateProjectionPullPage(
      nextCursor: nextCursor,
      changes: changes,
      hasMore: hasMore,
    );
  }

  static String _requiredString(Object? value, {String? fallback}) {
    final normalized = value?.toString().trim() ?? '';
    if (normalized.isNotEmpty) return normalized;
    if (fallback != null) return fallback;
    throw const LifeMateApiException(
      statusCode: 502,
      code: 'invalid_api_response',
      message: 'The service returned an invalid sync page.',
    );
  }

  static String? _optionalString(Object? value) {
    final normalized = value?.toString().trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  static DateTime? _optionalDate(Object? value) {
    final normalized = _optionalString(value);
    if (normalized == null) return null;
    final parsed = DateTime.tryParse(normalized);
    if (parsed == null) {
      throw const LifeMateApiException(
        statusCode: 502,
        code: 'invalid_api_response',
        message: 'The service returned an invalid sync timestamp.',
      );
    }
    return parsed.toUtc();
  }
}
