import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:lifemate_core/lifemate_core.dart';

import 'lifemate_api_client.dart' show AccessTokenProvider;

/// Authenticated lifemate-api adapter for the shared #831 replay engine.
///
/// Credentials remain ephemeral and are never copied into the durable mutation
/// envelope. Response bodies are deliberately not exposed to the shared core so
/// server messages or health data cannot enter retry state/telemetry by accident.
final class LifeMateHttpMutationReplayTransport
    implements LifeMateMutationReplayTransport {
  LifeMateHttpMutationReplayTransport({
    required Uri apiBaseUri,
    required AccessTokenProvider accessToken,
    http.Client? httpClient,
    this.transportTimeout = const Duration(seconds: 18),
  }) : _apiBaseUri = _normalizeBaseUri(apiBaseUri),
       _accessToken = accessToken,
       _httpClient = httpClient ?? http.Client();

  final Uri _apiBaseUri;
  final AccessTokenProvider _accessToken;
  final http.Client _httpClient;
  final Duration transportTimeout;
  bool _closed = false;

  static const Set<String> _allowedMutationMethods = <String>{
    'POST',
    'PUT',
    'PATCH',
    'DELETE',
  };

  @override
  Future<LifeMateMutationReplayResponse> send(
    LifeMateDurableMutation mutation,
  ) async {
    if (_closed) {
      throw StateError('LifeMate replay transport is closed.');
    }
    if (!_allowedMutationMethods.contains(mutation.method)) {
      throw StateError('Unsupported durable mutation method.');
    }

    final token = _accessToken()?.trim();
    if (token == null || token.isEmpty) {
      // Model missing/expired credentials as an authentication retry without
      // attempting a network request or persisting credentials with the action.
      return const LifeMateMutationReplayResponse(401);
    }

    final uri = _resolveApiPath(mutation.endpointPath);
    final request = http.Request(mutation.method, uri)
      ..headers.addAll(<String, String>{
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Idempotency-Key': mutation.mutationId,
        'X-LifeMate-Replay': '1',
      })
      ..body = jsonEncode(mutation.payload);

    try {
      final response = await _httpClient.send(request).timeout(transportTimeout);
      final statusCode = response.statusCode;
      await response.stream.drain<void>();
      return LifeMateMutationReplayResponse(statusCode);
    } on TimeoutException {
      throw const LifeMateMutationReplayTransportException();
    } on http.ClientException {
      throw const LifeMateMutationReplayTransportException();
    }
  }

  Uri _resolveApiPath(String endpointPath) {
    final relative = Uri.parse(endpointPath);
    if (relative.hasScheme ||
        relative.hasAuthority ||
        relative.host.isNotEmpty ||
        !relative.path.startsWith('/')) {
      throw StateError('Durable mutation endpoint must be API-relative.');
    }

    final basePath = _apiBaseUri.path.replaceFirst(RegExp(r'/+$'), '');
    final relativePath = relative.path.replaceFirst(RegExp(r'^/+'), '');
    final resolved = _apiBaseUri.replace(
      path: '$basePath/$relativePath',
      query: relative.hasQuery ? relative.query : null,
      fragment: '',
    );
    if (resolved.scheme != _apiBaseUri.scheme ||
        resolved.host != _apiBaseUri.host ||
        resolved.port != _apiBaseUri.port) {
      throw StateError('Durable mutation endpoint escaped the API origin.');
    }
    return resolved;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _httpClient.close();
  }

  static Uri _normalizeBaseUri(Uri value) {
    if (!value.hasScheme || value.host.isEmpty) {
      throw ArgumentError.value(value, 'apiBaseUri');
    }
    if (value.scheme != 'https' &&
        !(value.scheme == 'http' &&
            (value.host == 'localhost' || value.host == '127.0.0.1'))) {
      throw ArgumentError.value(
        value,
        'apiBaseUri',
        'LifeMate replay requires HTTPS outside localhost.',
      );
    }
    return value.replace(query: null, fragment: '');
  }
}
