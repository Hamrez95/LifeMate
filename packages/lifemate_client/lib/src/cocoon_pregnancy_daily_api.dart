import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'lifemate_api_client.dart'
    show AccessTokenProvider, LifeMateApiException;

enum CocoonPregnancyFeeling {
  comfortable('comfortable'),
  mixed('mixed'),
  difficult('difficult');

  const CocoonPregnancyFeeling(this.wireValue);
  final String wireValue;
}

enum CocoonPregnancyEnergy {
  low('low'),
  steady('steady'),
  high('high');

  const CocoonPregnancyEnergy(this.wireValue);
  final String wireValue;
}

enum CocoonPregnancySymptomIntensity {
  mild('mild'),
  moderate('moderate'),
  strong('strong');

  const CocoonPregnancySymptomIntensity(this.wireValue);
  final String wireValue;
}

enum CocoonPregnancyMood {
  veryLow('very_low'),
  low('low'),
  neutral('neutral'),
  good('good'),
  veryGood('very_good');

  const CocoonPregnancyMood(this.wireValue);
  final String wireValue;
}

/// Versioned catalog supplied by the authoritative Cocoon host/server layer.
///
/// The client does not invent symptom codes. [createSymptom] rejects any code
/// that is not present in this injected approved snapshot before network I/O.
class CocoonApprovedSymptomCatalog {
  CocoonApprovedSymptomCatalog({
    required String version,
    required Iterable<String> codes,
  }) : version = version.trim(),
       codes = Set<String>.unmodifiable(
         codes.map((code) => code.trim()).where((code) => code.isNotEmpty),
       ) {
    if (this.version.isEmpty) {
      throw ArgumentError.value(version, 'version', 'must not be empty.');
    }
  }

  final String version;
  final Set<String> codes;

  bool allows(String code) => codes.contains(code.trim());
}

class CocoonPregnancyCaptureRecord {
  const CocoonPregnancyCaptureRecord({
    required this.id,
    required this.episodeId,
    required this.observedAtUtc,
    required this.localDate,
    required this.timeZone,
    required this.version,
    this.feeling,
    this.energy,
    this.symptomCode,
    this.intensity,
    this.note,
    this.moodCode,
  });

  factory CocoonPregnancyCaptureRecord.fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString().trim() ?? '';
    final episodeId = json['episodeId']?.toString().trim() ?? '';
    final observedAtUtc = DateTime.tryParse(
      json['observedAtUtc']?.toString() ?? '',
    );
    final localDate = json['localDate']?.toString().trim() ?? '';
    final timeZone = json['timeZone']?.toString().trim() ?? '';
    final version = json['version'];
    if (id.isEmpty ||
        episodeId.isEmpty ||
        observedAtUtc == null ||
        localDate.isEmpty ||
        timeZone.isEmpty ||
        version is! num) {
      throw const FormatException('Invalid Cocoon daily capture payload.');
    }
    return CocoonPregnancyCaptureRecord(
      id: id,
      episodeId: episodeId,
      observedAtUtc: observedAtUtc.toUtc(),
      localDate: localDate,
      timeZone: timeZone,
      version: version.toInt(),
      feeling: json['feeling']?.toString(),
      energy: json['energy']?.toString(),
      symptomCode: json['symptomCode']?.toString(),
      intensity: json['intensity']?.toString(),
      note: json['note']?.toString(),
      moodCode: json['moodCode']?.toString(),
    );
  }

  final String id;
  final String episodeId;
  final DateTime observedAtUtc;
  final String localDate;
  final String timeZone;
  final int version;
  final String? feeling;
  final String? energy;
  final String? symptomCode;
  final String? intensity;
  final String? note;
  final String? moodCode;
}

class CocoonPregnancyDailyCaptures {
  const CocoonPregnancyDailyCaptures({
    required this.contractVersion,
    required this.episodeId,
    required this.checkIns,
    required this.symptoms,
    required this.moods,
  });

  factory CocoonPregnancyDailyCaptures.fromJson(Map<String, dynamic> json) {
    List<CocoonPregnancyCaptureRecord> records(Object? value) {
      if (value is! List) {
        throw const FormatException('Invalid Cocoon daily capture list.');
      }
      return value
          .whereType<Map>()
          .map(
            (item) => CocoonPregnancyCaptureRecord.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(growable: false);
    }

    final episodeId = json['episodeId']?.toString().trim() ?? '';
    if (episodeId.isEmpty) {
      throw const FormatException('Cocoon pregnancy episode is missing.');
    }
    return CocoonPregnancyDailyCaptures(
      contractVersion: (json['contractVersion'] as num?)?.toInt() ?? 0,
      episodeId: episodeId,
      checkIns: records(json['checkIns']),
      symptoms: records(json['symptoms']),
      moods: records(json['moods']),
    );
  }

  final int contractVersion;
  final String episodeId;
  final List<CocoonPregnancyCaptureRecord> checkIns;
  final List<CocoonPregnancyCaptureRecord> symptoms;
  final List<CocoonPregnancyCaptureRecord> moods;
}

class CocoonPregnancyDailyApiClient {
  CocoonPregnancyDailyApiClient({
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

  Future<CocoonPregnancyDailyCaptures> list({
    required DateTime fromDate,
    required DateTime toDate,
  }) async => CocoonPregnancyDailyCaptures.fromJson(
    await _object(
      'GET',
      '/api/v1/cocoon/pregnancy/daily-captures',
      query: {'fromDate': _date(fromDate), 'toDate': _date(toDate)},
    ),
  );

  Future<CocoonPregnancyCaptureRecord> createCheckIn({
    required String clientRequestId,
    required DateTime observedAtUtc,
    required String localDate,
    required String timeZone,
    required CocoonPregnancyFeeling feeling,
    required CocoonPregnancyEnergy energy,
  }) async {
    final envelope = await _object(
      'POST',
      '/api/v1/cocoon/pregnancy/check-ins',
      body: {
        'clientRequestId': _required(clientRequestId, 'clientRequestId'),
        'observedAtUtc': observedAtUtc.toUtc().toIso8601String(),
        'localDate': _required(localDate, 'localDate'),
        'timeZone': _required(timeZone, 'timeZone'),
        'feeling': feeling.wireValue,
        'energy': energy.wireValue,
      },
    );
    return _capture(envelope, 'checkIn');
  }

  Future<CocoonPregnancyCaptureRecord> createSymptom({
    required CocoonApprovedSymptomCatalog approvedCatalog,
    required String symptomCode,
    required CocoonPregnancySymptomIntensity intensity,
    required String clientRequestId,
    required DateTime observedAtUtc,
    required String localDate,
    required String timeZone,
    String? note,
  }) async {
    final code = _required(symptomCode, 'symptomCode');
    if (!approvedCatalog.allows(code)) {
      throw ArgumentError.value(
        symptomCode,
        'symptomCode',
        'must come from the injected approved symptom catalog.',
      );
    }
    final normalizedNote = note?.trim();
    if ((normalizedNote?.length ?? 0) > 400) {
      throw ArgumentError.value(note, 'note', 'must be at most 400 characters.');
    }
    final envelope = await _object(
      'POST',
      '/api/v1/cocoon/pregnancy/symptoms',
      body: {
        'clientRequestId': _required(clientRequestId, 'clientRequestId'),
        'observedAtUtc': observedAtUtc.toUtc().toIso8601String(),
        'localDate': _required(localDate, 'localDate'),
        'timeZone': _required(timeZone, 'timeZone'),
        'symptomCode': code,
        'intensity': intensity.wireValue,
        if (normalizedNote?.isNotEmpty ?? false) 'note': normalizedNote,
      },
    );
    return _capture(envelope, 'symptom');
  }

  Future<CocoonPregnancyCaptureRecord> createMood({
    required String clientRequestId,
    required DateTime observedAtUtc,
    required String localDate,
    required String timeZone,
    required CocoonPregnancyMood mood,
  }) async {
    final envelope = await _object(
      'POST',
      '/api/v1/cocoon/pregnancy/moods',
      body: {
        'clientRequestId': _required(clientRequestId, 'clientRequestId'),
        'observedAtUtc': observedAtUtc.toUtc().toIso8601String(),
        'localDate': _required(localDate, 'localDate'),
        'timeZone': _required(timeZone, 'timeZone'),
        'moodCode': mood.wireValue,
      },
    );
    return _capture(envelope, 'mood');
  }

  CocoonPregnancyCaptureRecord _capture(
    Map<String, dynamic> envelope,
    String key,
  ) {
    final value = envelope[key];
    if (value is! Map) {
      throw FormatException('Cocoon $key response is missing.');
    }
    return CocoonPregnancyCaptureRecord.fromJson(
      Map<String, dynamic>.from(value),
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

  static String _required(String value, String name) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(value, name, 'must not be empty.');
    }
    return normalized;
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
