import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'lifemate_api_client.dart' show AccessTokenProvider;
import 'offline_mutation_queue.dart';

typedef LifeMateAccountIdProvider = String? Function();

/// HTTP transport that durably journals only explicitly allowlisted,
/// idempotent treatment mutations before sending them.
///
/// The Authorization header is never persisted. Replays obtain the current
/// session token at send time and are restricted to the account that originally
/// created the queued action.
class LifeMateDurableHttpClient extends http.BaseClient {
  LifeMateDurableHttpClient({
    required AccessTokenProvider accessToken,
    required LifeMateAccountIdProvider accountId,
    LifeMateOfflineMutationQueue? queue,
    http.Client? inner,
  })  : _accessToken = accessToken,
        _accountId = accountId,
        _queue = queue ?? LifeMateOfflineMutationQueue(),
        _inner = inner ?? http.Client();

  final AccessTokenProvider _accessToken;
  final LifeMateAccountIdProvider _accountId;
  final LifeMateOfflineMutationQueue _queue;
  final http.Client _inner;
  bool _flushing = false;
  bool _closed = false;

  static final RegExp _doseReportPath = RegExp(
    r'/api/v1/dose-occurrences/[0-9a-f-]{36}/report$',
    caseSensitive: false,
  );

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_closed) throw http.ClientException('Client is closed.', request.url);

    final durable = await _durableCandidate(request);
    if (durable == null) {
      final response = await _inner.send(request);
      if (_isSuccess(response.statusCode)) {
        unawaited(flushPending());
      }
      return response;
    }

    LifeMateQueuedMutation? queued;
    try {
      queued = await _queue.enqueue(
        accountId: durable.accountId,
        method: request.method,
        uri: request.url,
        body: durable.body,
        clientRequestId: durable.clientRequestId,
      );
    } catch (_) {
      // Secure-storage availability must not block an otherwise-online dose or
      // appointment action. We still attempt the network request; if transport
      // is unavailable there is simply no false claim that it was queued.
      queued = null;
    }

    final copy = _copyRequest(request, durable.bodyBytes);
    try {
      final response = await _inner.send(copy);
      if (queued != null) {
        if (_isSuccess(response.statusCode) ||
            _isTerminalClientFailure(response.statusCode)) {
          await _queue.remove(queued.id);
        } else {
          await _queue.markAttempt(queued.id);
        }
      }
      if (_isSuccess(response.statusCode)) unawaited(flushPending());
      return response;
    } on http.ClientException {
      if (queued != null) {
        await _queue.markAttempt(queued.id);
        throw LifeMateOfflineQueuedException(
          clientRequestId: queued.clientRequestId,
        );
      }
      rethrow;
    }
  }

  Future<int> flushPending() async {
    if (_flushing || _closed) return 0;
    final accountId = _accountId()?.trim();
    final token = _accessToken()?.trim();
    if (accountId == null || accountId.isEmpty || token == null || token.isEmpty) {
      return 0;
    }

    _flushing = true;
    var synced = 0;
    try {
      final pending = await _queue.pendingForAccount(accountId);
      for (final mutation in pending) {
        final uri = Uri.tryParse(mutation.uri);
        if (uri == null || !_isAllowedPath(uri.path)) {
          await _queue.remove(mutation.id);
          continue;
        }

        final request = http.Request(mutation.method, uri)
          ..headers.addAll({
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
            'X-LifeMate-Replay': '1',
          })
          ..body = mutation.body;
        try {
          final response = await _inner.send(request);
          if (_isSuccess(response.statusCode)) {
            await response.stream.drain<void>();
            await _queue.remove(mutation.id);
            synced++;
            continue;
          }
          await response.stream.drain<void>();
          if (_isTerminalClientFailure(response.statusCode)) {
            // The server says this mutation is no longer valid (e.g. revoked
            // permission or stale object). Do not replay it forever.
            await _queue.remove(mutation.id);
            continue;
          }
          await _queue.markAttempt(mutation.id);
          // Preserve FIFO ordering on auth/transient/server failures.
          break;
        } on http.ClientException {
          await _queue.markAttempt(mutation.id);
          break;
        }
      }
    } finally {
      _flushing = false;
    }
    return synced;
  }

  Future<int> pendingCount() async {
    final accountId = _accountId()?.trim();
    if (accountId == null || accountId.isEmpty) return 0;
    return _queue.pendingCount(accountId);
  }

  Future<_DurableCandidate?> _durableCandidate(http.BaseRequest request) async {
    if (request.method != 'POST' || !_isAllowedPath(request.url.path)) {
      return null;
    }
    final accountId = _accountId()?.trim();
    if (accountId == null || accountId.isEmpty || request is! http.Request) {
      return null;
    }

    final bodyBytes = List<int>.from(request.bodyBytes);
    final body = utf8.decode(bodyBytes, allowMalformed: false);
    dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    final clientRequestId = decoded['clientRequestId']?.toString().trim();
    if (clientRequestId == null || clientRequestId.isEmpty) return null;
    return _DurableCandidate(
      accountId: accountId,
      body: body,
      bodyBytes: bodyBytes,
      clientRequestId: clientRequestId,
    );
  }

  bool _isAllowedPath(String path) =>
      path.endsWith('/api/v1/care-events') || _doseReportPath.hasMatch(path);

  static bool _isSuccess(int status) => status >= 200 && status < 300;

  static bool _isTerminalClientFailure(int status) =>
      status >= 400 &&
      status < 500 &&
      status != 401 &&
      status != 408 &&
      status != 429;

  static http.Request _copyRequest(http.BaseRequest source, List<int> bodyBytes) {
    final copy = http.Request(source.method, source.url)
      ..headers.addAll(source.headers)
      ..bodyBytes = bodyBytes
      ..followRedirects = source.followRedirects
      ..maxRedirects = source.maxRedirects
      ..persistentConnection = source.persistentConnection;
    return copy;
  }

  @override
  void close() {
    _closed = true;
    _inner.close();
    super.close();
  }
}

class _DurableCandidate {
  const _DurableCandidate({
    required this.accountId,
    required this.body,
    required this.bodyBytes,
    required this.clientRequestId,
  });

  final String accountId;
  final String body;
  final List<int> bodyBytes;
  final String clientRequestId;
}
