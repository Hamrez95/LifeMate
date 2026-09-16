import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'lifemate_api_client.dart'
    show AccessTokenProvider, LifeMateApiException;

enum CocoonPregnancyRecordCategory {
  pregnancy('pregnancy'),
  checkIns('check_ins'),
  symptoms('symptoms'),
  moods('moods'),
  measurements('measurements'),
  appointments('appointments'),
  medications('medications');

  const CocoonPregnancyRecordCategory(this.wireValue);
  final String wireValue;
}

class CocoonPregnancyRecordItem {
  const CocoonPregnancyRecordItem({
    required this.id,
    required this.sourceKind,
    required this.sourceId,
    required this.category,
    required this.occurredAtUtc,
    required this.localDate,
    required this.type,
    required this.summary,
    this.deepLink,
    this.sourceVersion,
  });

  factory CocoonPregnancyRecordItem.fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString().trim() ?? '';
    final sourceKind = json['sourceKind']?.toString().trim() ?? '';
    final sourceId = json['sourceId']?.toString().trim() ?? '';
    final category = json['category']?.toString().trim() ?? '';
    final occurredAtUtc = DateTime.tryParse(
      json['occurredAtUtc']?.toString() ?? '',
    );
    final localDate = json['localDate']?.toString().trim() ?? '';
    final type = json['type']?.toString().trim() ?? '';
    final summary = json['summary'];
    if (id.isEmpty ||
        sourceKind.isEmpty ||
        sourceId.isEmpty ||
        category.isEmpty ||
        occurredAtUtc == null ||
        localDate.isEmpty ||
        type.isEmpty ||
        summary is! Map) {
      throw const FormatException('Invalid Cocoon pregnancy record item.');
    }
    return CocoonPregnancyRecordItem(
      id: id,
      sourceKind: sourceKind,
      sourceId: sourceId,
      category: category,
      occurredAtUtc: occurredAtUtc.toUtc(),
      localDate: localDate,
      type: type,
      summary: Map<String, dynamic>.unmodifiable(
        Map<String, dynamic>.from(summary),
      ),
      deepLink: json['deepLink']?.toString(),
      sourceVersion: (json['sourceVersion'] as num?)?.toInt(),
    );
  }

  final String id;
  final String sourceKind;
  final String sourceId;
  final String category;
  final DateTime occurredAtUtc;
  final String localDate;
  final String type;
  final Map<String, dynamic> summary;
  final String? deepLink;
  final int? sourceVersion;
}

class CocoonPregnancyRecordsPage {
  const CocoonPregnancyRecordsPage({
    required this.contractVersion,
    required this.episodeId,
    required this.fromDate,
    required this.toDate,
    required this.categories,
    required this.items,
    required this.nextCursor,
    required this.sourceOfTruth,
  });

  factory CocoonPregnancyRecordsPage.fromJson(Map<String, dynamic> json) {
    final episodeId = json['episodeId']?.toString().trim() ?? '';
    final fromDate = json['fromDate']?.toString().trim() ?? '';
    final toDate = json['toDate']?.toString().trim() ?? '';
    final rawCategories = json['categories'];
    final rawItems = json['items'];
    final sourceOfTruth = json['sourceOfTruth']?.toString().trim() ?? '';
    if (episodeId.isEmpty ||
        fromDate.isEmpty ||
        toDate.isEmpty ||
        rawCategories is! List ||
        rawItems is! List ||
        sourceOfTruth != 'composed_canonical_domains') {
      throw const FormatException('Invalid Cocoon pregnancy records payload.');
    }
    return CocoonPregnancyRecordsPage(
      contractVersion: (json['contractVersion'] as num?)?.toInt() ?? 0,
      episodeId: episodeId,
      fromDate: fromDate,
      toDate: toDate,
      categories: rawCategories.map((value) => value.toString()).toList(
        growable: false,
      ),
      items: rawItems
          .whereType<Map>()
          .map(
            (item) => CocoonPregnancyRecordItem.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(growable: false),
      nextCursor: json['nextCursor']?.toString(),
      sourceOfTruth: sourceOfTruth,
    );
  }

  final int contractVersion;
  final String episodeId;
  final String fromDate;
  final String toDate;
  final List<String> categories;
  final List<CocoonPregnancyRecordItem> items;
  final String? nextCursor;
  final String sourceOfTruth;
}

class CocoonPregnancyRecordsApiClient {
  CocoonPregnancyRecordsApiClient({
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

  Future<CocoonPregnancyRecordsPage> list({
    required DateTime fromDate,
    required DateTime toDate,
    Set<CocoonPregnancyRecordCategory>? categories,
    int limit = 30,
    String? cursor,
  }) async {
    if (limit < 1 || limit > 100) {
      throw ArgumentError.value(limit, 'limit', 'must be between 1 and 100.');
    }
    final token = _accessToken();
    if (token == null || token.isEmpty) {
      throw const LifeMateApiException(
        statusCode: 401,
        code: 'session_missing',
        message: 'Authentication session is missing.',
      );
    }
    final query = <String, String>{
      'fromDate': _date(fromDate),
      'toDate': _date(toDate),
      'limit': '$limit',
      if (categories != null && categories.isNotEmpty)
        'categories': categories.map((value) => value.wireValue).join(','),
      if (cursor != null && cursor.trim().isNotEmpty) 'cursor': cursor.trim(),
    };
    final uri = _resolve('/api/v1/cocoon/pregnancy/records').replace(
      queryParameters: query,
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
    return CocoonPregnancyRecordsPage.fromJson(decoded);
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
