import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config.dart';
import 'lifemate_api_client.dart';

typedef LifeMateRemoteConfigTokenProvider = String? Function();
typedef LifeMateRemoteConfigCacheRead = Future<String?> Function(String key);
typedef LifeMateRemoteConfigCacheWrite = Future<void> Function(String key, String value);

@immutable
class LifeMateRemoteControl {
  const LifeMateRemoteControl({
    required this.key,
    required this.kind,
    required this.valueType,
    required this.value,
    required this.definitionVersion,
    required this.source,
    required this.ruleVersion,
    required this.failClosed,
  });

  factory LifeMateRemoteControl.fromJson(Map<String, dynamic> json) =>
      LifeMateRemoteControl(
        key: json['key']?.toString() ?? '',
        kind: json['kind']?.toString() ?? '',
        valueType: json['valueType']?.toString() ?? '',
        value: json['value'],
        definitionVersion: int.tryParse(json['definitionVersion']?.toString() ?? '') ?? 0,
        source: json['source']?.toString() ?? 'default',
        ruleVersion: int.tryParse(json['ruleVersion']?.toString() ?? ''),
        failClosed: json['failClosed'] == true,
      );

  final String key;
  final String kind;
  final String valueType;
  final Object? value;
  final int definitionVersion;
  final String source;
  final int? ruleVersion;
  final bool failClosed;
}

enum LifeMateUpdateState { current, soft, force }

@immutable
class LifeMateUpdatePolicy {
  const LifeMateUpdatePolicy({
    required this.state,
    required this.minimumSupportedVersion,
    required this.recommendedVersion,
    required this.reasonCode,
    required this.messageKey,
    required this.policyVersion,
  });

  factory LifeMateUpdatePolicy.fromJson(Map<String, dynamic> json) {
    final raw = json['updateState']?.toString();
    return LifeMateUpdatePolicy(
      state: switch (raw) {
        'force' => LifeMateUpdateState.force,
        'soft' => LifeMateUpdateState.soft,
        _ => LifeMateUpdateState.current,
      },
      minimumSupportedVersion: _nullable(json['minimumSupportedVersion']),
      recommendedVersion: _nullable(json['recommendedVersion']),
      reasonCode: json['reasonCode']?.toString() ?? 'Routine',
      messageKey: _nullable(json['messageKey']),
      policyVersion: int.tryParse(json['policyVersion']?.toString() ?? '') ?? 0,
    );
  }

  final LifeMateUpdateState state;
  final String? minimumSupportedVersion;
  final String? recommendedVersion;
  final String reasonCode;
  final String? messageKey;
  final int policyVersion;

  static String? _nullable(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}

@immutable
class LifeMateRuntimeConfigSnapshot {
  const LifeMateRuntimeConfigSnapshot({
    required this.product,
    required this.platform,
    required this.controls,
    required this.updatePolicy,
    required this.snapshotVersion,
    required this.fetchedAtUtc,
    required this.cacheTtlSeconds,
    required this.fromCache,
  });

  factory LifeMateRuntimeConfigSnapshot.fromJson(
    Map<String, dynamic> json, {
    bool fromCache = false,
  }) => LifeMateRuntimeConfigSnapshot(
        product: json['product']?.toString() ?? '',
        platform: json['platform']?.toString() ?? '',
        controls: {
          for (final raw in (json['controls'] as List<dynamic>? ?? const []))
            if (raw is Map)
              Map<String, dynamic>.from(raw)['key']?.toString() ?? '':
                  LifeMateRemoteControl.fromJson(Map<String, dynamic>.from(raw)),
        }..remove(''),
        updatePolicy: LifeMateUpdatePolicy.fromJson(
          Map<String, dynamic>.from(json['updatePolicy'] as Map? ?? const {}),
        ),
        snapshotVersion: json['snapshotVersion']?.toString() ?? 'unknown',
        fetchedAtUtc: DateTime.tryParse(json['fetchedAtUtc']?.toString() ?? '')?.toUtc() ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        cacheTtlSeconds: int.tryParse(json['cacheTtlSeconds']?.toString() ?? '') ?? 60,
        fromCache: fromCache,
      );

  final String product;
  final String platform;
  final Map<String, LifeMateRemoteControl> controls;
  final LifeMateUpdatePolicy updatePolicy;
  final String snapshotVersion;
  final DateTime fetchedAtUtc;
  final int cacheTtlSeconds;
  final bool fromCache;

  bool isFresh(DateTime now) =>
      now.toUtc().difference(fetchedAtUtc) <= Duration(seconds: cacheTtlSeconds);

  bool boolFlag(String key, {bool defaultValue = false, DateTime? now}) {
    final control = controls[key];
    if (control == null || control.kind != 'FeatureFlag' || control.valueType != 'Boolean') {
      return defaultValue;
    }
    final staleFor = (now ?? DateTime.now()).toUtc().difference(fetchedAtUtc);
    if (staleFor > const Duration(hours: 24) && control.failClosed) return false;
    return control.value is bool ? control.value as bool : (control.failClosed ? false : defaultValue);
  }

  Map<String, dynamic> toJson() => {
        'product': product,
        'platform': platform,
        'controls': controls.values
            .map((control) => {
                  'key': control.key,
                  'kind': control.kind,
                  'valueType': control.valueType,
                  'value': control.value,
                  'definitionVersion': control.definitionVersion,
                  'source': control.source,
                  'ruleVersion': control.ruleVersion,
                  'failClosed': control.failClosed,
                })
            .toList(growable: false),
        'updatePolicy': {
          'updateState': updatePolicy.state.name,
          'minimumSupportedVersion': updatePolicy.minimumSupportedVersion,
          'recommendedVersion': updatePolicy.recommendedVersion,
          'reasonCode': updatePolicy.reasonCode,
          'messageKey': updatePolicy.messageKey,
          'policyVersion': updatePolicy.policyVersion,
        },
        'snapshotVersion': snapshotVersion,
        'fetchedAtUtc': fetchedAtUtc.toIso8601String(),
        'cacheTtlSeconds': cacheTtlSeconds,
      };
}

class LifeMateRemoteConfigClient {
  LifeMateRemoteConfigClient({
    required Uri baseUri,
    required this.product,
    required this.currentVersion,
    required LifeMateRemoteConfigTokenProvider accessToken,
    this.beta = false,
    String? platform,
    http.Client? httpClient,
    LifeMateRemoteConfigCacheRead? cacheRead,
    LifeMateRemoteConfigCacheWrite? cacheWrite,
  })  : _baseUri = baseUri,
        platform = platform ?? _platformName(),
        _accessToken = accessToken,
        _http = httpClient ?? http.Client(),
        _cacheRead = cacheRead ?? _secureRead,
        _cacheWrite = cacheWrite ?? _secureWrite;

  factory LifeMateRemoteConfigClient.fromEnvironment({
    required String product,
    required String currentVersion,
    bool beta = false,
  }) {
    final config = AppConfig.fromEnvironment();
    return LifeMateRemoteConfigClient(
      baseUri: config.apiBaseUri,
      product: product,
      currentVersion: currentVersion,
      beta: beta,
      accessToken: () => Supabase.instance.client.auth.currentSession?.accessToken,
    );
  }

  static const _storage = FlutterSecureStorage();
  static const _timeout = Duration(seconds: 12);
  final Uri _baseUri;
  final String product;
  final String platform;
  final String currentVersion;
  final bool beta;
  final LifeMateRemoteConfigTokenProvider _accessToken;
  final http.Client _http;
  final LifeMateRemoteConfigCacheRead _cacheRead;
  final LifeMateRemoteConfigCacheWrite _cacheWrite;

  String get _cacheKey => 'lifemate.runtime-config.$product.$platform';

  Future<LifeMateRuntimeConfigSnapshot> load({bool forceRefresh = false}) async {
    final cached = await _readCached();
    if (!forceRefresh && cached != null && cached.isFresh(DateTime.now())) return cached;
    try {
      final fresh = await _fetch();
      await _cacheWrite(_cacheKey, jsonEncode(fresh.toJson()));
      return fresh;
    } catch (_) {
      if (cached != null) return cached;
      rethrow;
    }
  }

  Future<void> recordVersionPresence({String? buildNumber, String? rolloutCohort}) async {
    final token = _requireToken();
    final uri = _baseUri.replace(
      path: '${_baseUri.path.replaceFirst(RegExp(r'/$'), '')}/api/v1/product/version-presence',
    );
    final response = await _http
        .post(
          uri,
          headers: {
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
            'Idempotency-Key': LifeMateApiClient.createClientRequestId(),
          },
          body: jsonEncode({
            'product': product,
            'platform': platform,
            'appVersion': currentVersion,
            'buildNumber': buildNumber ?? _buildFromVersion(currentVersion),
            if (rolloutCohort != null) 'rolloutCohort': rolloutCohort,
          }),
        )
        .timeout(_timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _problem(response, 'Product version presence could not be recorded.');
    }
  }

  Future<LifeMateRuntimeConfigSnapshot> _fetch() async {
    final token = _requireToken();
    final path = '${_baseUri.path.replaceFirst(RegExp(r'/$'), '')}/api/v1/product/runtime-config';
    final uri = _baseUri.replace(path: path, queryParameters: {
      'product': product,
      'platform': platform,
      'currentVersion': currentVersion,
      'beta': beta.toString(),
    });
    final response = await _http
        .get(uri, headers: {'Accept': 'application/json', 'Authorization': 'Bearer $token'})
        .timeout(_timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _problem(response, 'Runtime configuration could not be loaded.');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) throw const FormatException('Runtime configuration is invalid.');
    return LifeMateRuntimeConfigSnapshot.fromJson(Map<String, dynamic>.from(decoded));
  }

  Future<LifeMateRuntimeConfigSnapshot?> _readCached() async {
    try {
      final raw = await _cacheRead(_cacheKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return LifeMateRuntimeConfigSnapshot.fromJson(
        Map<String, dynamic>.from(decoded),
        fromCache: true,
      );
    } catch (_) {
      return null;
    }
  }

  String _requireToken() {
    final token = _accessToken();
    if (token == null || token.isEmpty) {
      throw const LifeMateApiException(
        statusCode: 401,
        code: 'session_missing',
        message: 'Authentication session is missing.',
      );
    }
    return token;
  }

  LifeMateApiException _problem(http.Response response, String fallback) {
    Map<String, dynamic> value = const {};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) value = Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return LifeMateApiException(
      statusCode: response.statusCode,
      code: value['code']?.toString() ?? 'request_failed',
      message: value['detail']?.toString() ?? value['message']?.toString() ?? fallback,
    );
  }

  void close() => _http.close();

  static Future<String?> _secureRead(String key) => _storage.read(key: key);
  static Future<void> _secureWrite(String key, String value) => _storage.write(key: key, value: value);
}

String _platformName() {
  if (kIsWeb) return 'web';
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => 'android',
    TargetPlatform.iOS => 'ios',
    TargetPlatform.windows => 'windows',
    TargetPlatform.macOS => 'macos',
    TargetPlatform.linux => 'linux',
    TargetPlatform.fuchsia => 'unknown',
  };
}

String _buildFromVersion(String version) {
  final plus = version.indexOf('+');
  return plus < 0 || plus == version.length - 1 ? 'unknown' : version.substring(plus + 1);
}
