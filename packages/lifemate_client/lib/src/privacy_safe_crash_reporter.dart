import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'app_config.dart';
import 'lifemate_auth.dart';

typedef LifeMateCrashTokenProvider = Future<String?> Function();

enum LifeMateCrashSource {
  flutterFramework('flutter_framework'),
  platformDispatcher('platform_dispatcher'),
  zone('zone');

  const LifeMateCrashSource(this.wireName);
  final String wireName;
}

@immutable
class PrivacySafeCrashEvent {
  const PrivacySafeCrashEvent({
    required this.eventId,
    required this.application,
    required this.releaseVersion,
    required this.platform,
    required this.source,
    required this.errorType,
    required this.stackFingerprint,
    required this.fatal,
  });

  factory PrivacySafeCrashEvent.fromError({
    required String application,
    required String releaseVersion,
    required Object error,
    required StackTrace stackTrace,
    required LifeMateCrashSource source,
    required bool fatal,
  }) {
    return PrivacySafeCrashEvent(
      eventId: _newEventId(),
      application: application.trim().toLowerCase(),
      releaseVersion: _safeReleaseVersion(releaseVersion),
      platform: _platformName(),
      source: source.wireName,
      errorType: _safeErrorType(error.runtimeType.toString()),
      stackFingerprint: _stackFingerprint(stackTrace),
      fatal: fatal,
    );
  }

  final String eventId;
  final String application;
  final String releaseVersion;
  final String platform;
  final String source;
  final String errorType;
  final String stackFingerprint;
  final bool fatal;

  Map<String, Object> toJson() => <String, Object>{
    'eventId': eventId,
    'application': application,
    'releaseVersion': releaseVersion,
    'platform': platform,
    'source': source,
    'errorType': errorType,
    'stackFingerprint': stackFingerprint,
    'fatal': fatal,
  };
}

class LifeMateCrashReporter {
  LifeMateCrashReporter({
    required this.config,
    required this.application,
    required this.releaseVersion,
    LifeMateCrashTokenProvider? accessToken,
    http.Client? httpClient,
  }) : _accessToken = accessToken ?? LifeMateAuth.getValidAccessToken,
       _http = httpClient ?? http.Client();

  final AppConfig config;
  final String application;
  final String releaseVersion;
  final LifeMateCrashTokenProvider _accessToken;
  final http.Client _http;
  bool _handlersInstalled = false;

  Uri get _telemetryUri => Uri.parse(
    '${config.supabaseUrl.replaceFirst(RegExp(r'/+$'), '')}/functions/v1/lifemate-telemetry',
  );

  void installGlobalHandlers() {
    if (_handlersInstalled) return;
    _handlersInstalled = true;

    final previousFlutterHandler = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      if (kDebugMode) {
        previousFlutterHandler?.call(details);
      }
      unawaited(
        report(
          details.exception,
          details.stack ?? StackTrace.empty,
          source: LifeMateCrashSource.flutterFramework,
          fatal: false,
        ),
      );
    };

    final previousPlatformHandler = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      if (kDebugMode && previousPlatformHandler != null) {
        previousPlatformHandler(error, stack);
      }
      unawaited(
        report(
          error,
          stack,
          source: LifeMateCrashSource.platformDispatcher,
          fatal: true,
        ),
      );
      // In release builds, mark the error handled so the engine does not print
      // a raw exception/stack containing user or health context to system logs.
      return true;
    };
  }

  Future<void> report(
    Object error,
    StackTrace stackTrace, {
    required LifeMateCrashSource source,
    required bool fatal,
  }) async {
    if (!config.isConfigured) return;

    String? token;
    try {
      token = await _accessToken();
    } catch (_) {
      return;
    }
    if (token == null || token.isEmpty) return;

    final event = PrivacySafeCrashEvent.fromError(
      application: application,
      releaseVersion: releaseVersion,
      error: error,
      stackTrace: stackTrace,
      source: source,
      fatal: fatal,
    );

    try {
      await _http
          .post(
            _telemetryUri,
            headers: <String, String>{
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
              'apikey': config.supabasePublishableKey,
              'Content-Type': 'application/json',
            },
            body: jsonEncode(event.toJson()),
          )
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      // Crash reporting must never recursively crash, block startup, or print a
      // raw exception/token while handling another failure.
    }
  }

  void close() => _http.close();
}

String _safeReleaseVersion(String value) {
  final normalized = value.trim();
  if (RegExp(r'^[A-Za-z0-9][A-Za-z0-9._+-]{0,79}$').hasMatch(normalized)) {
    return normalized;
  }
  return 'unknown';
}

String _safeErrorType(String value) {
  var normalized = value.replaceAll(RegExp(r'[^A-Za-z0-9_.]'), '_');
  if (normalized.isEmpty) normalized = 'Error';
  if (!RegExp(r'^[A-Za-z_]').hasMatch(normalized)) {
    normalized = 'Error_$normalized';
  }
  if (normalized.length > 80) normalized = normalized.substring(0, 80);
  return normalized;
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

String _stackFingerprint(StackTrace stackTrace) {
  // The raw stack never leaves the process. FNV-1a is used only as a compact
  // grouping fingerprint, not as a security primitive. BigInt keeps the
  // unsigned 64-bit arithmetic deterministic across Dart native and web while
  // avoiding integer literals outside Dart's signed 64-bit source range.
  var hash = BigInt.parse('14695981039346656037');
  final prime = BigInt.from(1099511628211);
  final mask64 = BigInt.parse('ffffffffffffffff', radix: 16);
  for (final codeUnit in stackTrace.toString().codeUnits) {
    hash ^= BigInt.from(codeUnit);
    hash = (hash * prime) & mask64;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}

String _newEventId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}
