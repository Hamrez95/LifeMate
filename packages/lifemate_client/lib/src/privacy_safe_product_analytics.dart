import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'app_config.dart';
import 'lifemate_auth.dart';

typedef LifeMateProductAnalyticsTokenProvider = Future<String?> Function();

enum LifeMateProductEvent {
  appOpen('app_opened'),
  authLoginSucceeded('auth_login_succeeded'),
  authSessionRestored('auth_session_restored'),
  onboardingStarted('onboarding_started'),
  onboardingCompleted('onboarding_completed'),
  carePairingStarted('care_pairing_started'),
  carePairingCompleted('care_pairing_completed'),
  careAccessRevoked('care_access_revoked'),
  offlineQueueEnqueued('offline_queue_enqueued'),
  offlineQueueRecovered('offline_queue_recovered');

  const LifeMateProductEvent(this.wireName);
  final String wireName;
}

enum LifeMateLocaleFamily {
  fa('fa'),
  en('en'),
  other('other');

  const LifeMateLocaleFamily(this.wireName);
  final String wireName;
}

enum LifeMateConnectivityClass {
  online('online'),
  offline('offline'),
  recovering('recovering'),
  unknown('unknown');

  const LifeMateConnectivityClass(this.wireName);
  final String wireName;
}

enum LifeMateTelemetryOutcome {
  success('success'),
  failure('failure'),
  cancelled('cancelled'),
  queued('queued'),
  replayed('replayed'),
  notApplicable('not_applicable');

  const LifeMateTelemetryOutcome(this.wireName);
  final String wireName;
}

@immutable
class PrivacySafeProductEvent {
  const PrivacySafeProductEvent({
    required this.eventId,
    required this.application,
    required this.releaseVersion,
    required this.platform,
    required this.eventName,
    required this.localeFamily,
    required this.connectivity,
    required this.outcome,
  });

  factory PrivacySafeProductEvent.create({
    required String application,
    required String releaseVersion,
    required LifeMateProductEvent event,
    LifeMateLocaleFamily localeFamily = LifeMateLocaleFamily.other,
    LifeMateConnectivityClass connectivity = LifeMateConnectivityClass.unknown,
    LifeMateTelemetryOutcome outcome = LifeMateTelemetryOutcome.notApplicable,
  }) {
    final normalizedApplication = _safeApplication(application);
    if (normalizedApplication == null) {
      throw ArgumentError.value(application, 'application');
    }
    return PrivacySafeProductEvent(
      eventId: _newEventId(),
      application: normalizedApplication,
      releaseVersion: _safeReleaseVersion(releaseVersion),
      platform: _platformName(),
      eventName: event.wireName,
      localeFamily: localeFamily.wireName,
      connectivity: connectivity.wireName,
      outcome: outcome.wireName,
    );
  }

  final String eventId;
  final String application;
  final String releaseVersion;
  final String platform;
  final String eventName;
  final String localeFamily;
  final String connectivity;
  final String outcome;

  Map<String, Object> toJson() => <String, Object>{
    'kind': 'product',
    'eventId': eventId,
    'application': application,
    'releaseVersion': releaseVersion,
    'platform': platform,
    'eventName': eventName,
    'localeFamily': localeFamily,
    'connectivity': connectivity,
    'outcome': outcome,
  };
}

class LifeMateProductAnalytics {
  LifeMateProductAnalytics({
    required this.config,
    required this.application,
    required this.releaseVersion,
    LifeMateProductAnalyticsTokenProvider? accessToken,
    http.Client? httpClient,
  }) : _accessToken = accessToken ?? LifeMateAuth.getValidAccessToken,
       _http = httpClient ?? http.Client();

  final AppConfig config;
  final String application;
  final String releaseVersion;
  final LifeMateProductAnalyticsTokenProvider _accessToken;
  final http.Client _http;

  Uri get _telemetryUri => Uri.parse(
    '${config.supabaseUrl.replaceFirst(RegExp(r'/+$'), '')}/functions/v1/lifemate-telemetry',
  );

  Future<void> track(
    LifeMateProductEvent event, {
    LifeMateLocaleFamily localeFamily = LifeMateLocaleFamily.other,
    LifeMateConnectivityClass connectivity = LifeMateConnectivityClass.unknown,
    LifeMateTelemetryOutcome outcome = LifeMateTelemetryOutcome.notApplicable,
  }) async {
    if (!config.isConfigured || _safeApplication(application) == null) return;

    String? token;
    try {
      token = await _accessToken();
    } catch (_) {
      return;
    }
    if (token == null || token.isEmpty) return;

    final envelope = PrivacySafeProductEvent.create(
      application: application,
      releaseVersion: releaseVersion,
      event: event,
      localeFamily: localeFamily,
      connectivity: connectivity,
      outcome: outcome,
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
            body: jsonEncode(envelope.toJson()),
          )
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      // Product analytics is non-critical. It must never block the experience,
      // recurse into crash handling, or print a token/user/health payload.
    }
  }

  void close() => _http.close();
}

String? _safeApplication(String value) {
  final normalized = value.trim().toLowerCase();
  return normalized == 'wellmate' || normalized == 'caremate'
      ? normalized
      : null;
}

String _safeReleaseVersion(String value) {
  final normalized = value.trim();
  if (RegExp(r'^[A-Za-z0-9][A-Za-z0-9._+-]{0,79}$').hasMatch(normalized)) {
    return normalized;
  }
  return 'unknown';
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
