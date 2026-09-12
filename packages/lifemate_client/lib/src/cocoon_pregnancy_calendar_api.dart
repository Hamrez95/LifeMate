import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'lifemate_api_client.dart'
    show AccessTokenProvider, LifeMateApiException;

enum CocoonPregnancyCalendarClassification {
  prenatal('prenatal'),
  ultrasound('ultrasound'),
  checkup('checkup'),
  labTest('lab_test'),
  injection('injection'),
  other('other');

  const CocoonPregnancyCalendarClassification(this.wireValue);

  final String wireValue;

  static CocoonPregnancyCalendarClassification fromWire(Object? value) {
    final wire = value?.toString() ?? '';
    return CocoonPregnancyCalendarClassification.values.firstWhere(
      (item) => item.wireValue == wire,
      orElse: () => throw FormatException(
        'Unsupported pregnancy calendar classification: $wire',
      ),
    );
  }
}

class CocoonPregnancyCalendarItem {
  const CocoonPregnancyCalendarItem({
    required this.id,
    required this.classification,
    required this.careEvent,
  });

  factory CocoonPregnancyCalendarItem.fromJson(Map<String, dynamic> json) {
    final id = (json['seriesId'] ?? json['id'])?.toString().trim() ?? '';
    if (id.isEmpty) {
      throw const FormatException('Pregnancy calendar care-event id is missing.');
    }
    return CocoonPregnancyCalendarItem(
      id: id,
      classification: CocoonPregnancyCalendarClassification.fromWire(
        json['pregnancyClassification'],
      ),
      careEvent: Map<String, dynamic>.unmodifiable(json),
    );
  }

  final String id;
  final CocoonPregnancyCalendarClassification classification;

  /// Canonical care-event payload returned by the shared care-event domain.
  /// Cocoon does not create a second appointment model or store.
  final Map<String, dynamic> careEvent;
}

class CocoonPregnancyCalendarPage {
  const CocoonPregnancyCalendarPage({
    required this.contractVersion,
    required this.episodeId,
    required this.fromDate,
    required this.toDate,
    required this.items,
  });

  factory CocoonPregnancyCalendarPage.fromJson(Map<String, dynamic> json) {
    final items = json['items'];
    if (items is! List) {
      throw const FormatException('Pregnancy calendar items are missing.');
    }
    final episodeId = json['episodeId']?.toString().trim() ?? '';
    final fromDate = json['fromDate']?.toString().trim() ?? '';
    final toDate = json['toDate']?.toString().trim() ?? '';
    if (episodeId.isEmpty || fromDate.isEmpty || toDate.isEmpty) {
      throw const FormatException('Pregnancy calendar envelope is invalid.');
    }
    return CocoonPregnancyCalendarPage(
      contractVersion: (json['contractVersion'] as num?)?.toInt() ?? 0,
      episodeId: episodeId,
      fromDate: fromDate,
      toDate: toDate,
      items: items
          .whereType<Map>()
          .map(
            (item) => CocoonPregnancyCalendarItem.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(growable: false),
    );
  }

  final int contractVersion;
  final String episodeId;
  final String fromDate;
  final String toDate;
  final List<CocoonPregnancyCalendarItem> items;
}

class CocoonPregnancyCalendarApiClient {
  CocoonPregnancyCalendarApiClient({
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

  Future<CocoonPregnancyCalendarPage> list({
    required DateTime fromDate,
    required DateTime toDate,
  }) async => CocoonPregnancyCalendarPage.fromJson(
    await _object(
      'GET',
      '/api/v1/cocoon/pregnancy/calendar',
      query: {'fromDate': _date(fromDate), 'toDate': _date(toDate)},
    ),
  );

  /// Creates a shared canonical care event and links it to the active pregnancy.
  /// `careEvent` must contain the canonical care-event `clientRequestId`; the
  /// same payload may then be retried without creating a second appointment.
  Future<Map<String, dynamic>> createEvent({
    required Map<String, dynamic> careEvent,
    required CocoonPregnancyCalendarClassification classification,
  }) async {
    final clientRequestId = careEvent['clientRequestId']?.toString().trim() ?? '';
    if (clientRequestId.isEmpty) {
      throw ArgumentError.value(
        clientRequestId,
        'careEvent.clientRequestId',
        'Canonical care-event mutations require a stable client request id.',
      );
    }
    return _object(
      'POST',
      '/api/v1/cocoon/pregnancy/calendar/events',
      body: {
        'careEvent': careEvent,
        'classification': classification.wireValue,
      },
    );
  }

  Future<Map<String, dynamic>> linkExisting({
    required String careEventId,
    required CocoonPregnancyCalendarClassification classification,
  }) {
    final normalizedId = careEventId.trim();
    if (normalizedId.isEmpty) {
      throw ArgumentError.value(careEventId, 'careEventId', 'must not be empty.');
    }
    return _object(
      'POST',
      '/api/v1/cocoon/pregnancy/calendar/links',
      body: {
        'careEventId': normalizedId,
        'classification': classification.wireValue,
      },
    );
  }

  Future<Map<String, dynamic>> _object(
    String method,
    String path, {
    Map<String, String>? query,
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
    var uri = _resolve(path);
    if (query != null) uri = uri.replace(queryParameters: query);
    final headers = <String, String>{
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
      if (body != null) 'Content-Type': 'application/json',
    };

    late http.Response response;
    try {
      response = switch (method) {
        'GET' => await _http.get(uri, headers: headers).timeout(_timeout),
        'POST' => await _http
            .post(uri, headers: headers, body: jsonEncode(body))
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
      throw const FormatException('LifeMate API returned a non-object payload.');
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
