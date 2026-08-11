import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'lifemate_api_client.dart' show AccessTokenProvider;
import 'offline_mutation_queue.dart';

typedef LifeMateAccountIdProvider = String? Function();

class LifeMateDurableHttpClient extends http.BaseClient {
  LifeMateDurableHttpClient({
    required Uri apiBaseUri,
    required AccessTokenProvider accessToken,
    required LifeMateAccountIdProvider accountId,
    LifeMateOfflineMutationQueue? queue,
    http.Client? inner,
    Duration transportTimeout = const Duration(seconds: 18),
  })  : _apiBaseUri = apiBaseUri,
        _accessToken = accessToken,
        _accountId = accountId,
        _queue = queue ?? LifeMateOfflineMutationQueue(),
        _inner = inner ?? http.Client(),
        _transportTimeout = transportTimeout;

  final Uri _apiBaseUri;
  final AccessTokenProvider _accessToken;
  final LifeMateAccountIdProvider _accountId;
  final LifeMateOfflineMutationQueue _queue;
  final http.Client _inner;
  final Duration _transportTimeout;
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
      if (_isSuccess(response.statusCode)) unawaited(flushPending());
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
      queued = null;
    }

    final copy = _copyRequest(request, durable.bodyBytes);
    try {
      final response = await _inner.send(copy).timeout(_transportTimeout);
      if (queued != null) {
        if (_isSuccess(response.statusCode) ||
            _isTerminalClientFailure(response.statusCode)) {
          await _bestEffort(() => _queue.remove(queued!.id));
        } else {
          // 408/429/5xx leave the mutation durably queued. Do not return the
          // transient failure to the API layer because that would trigger
          // retries/new request IDs and make the UI claim the local action
          // failed even though it is retained for replay.
          await response.stream.drain<void>();
          throw LifeMateOfflineQueuedException(
            clientRequestId: queued.clientRequestId,
          );
        }
      }
      if (_isSuccess(response.statusCode)) unawaited(flushPending());
      return response;
    } on LifeMateOfflineQueuedException {
      rethrow;
    } on TimeoutException {
      if (queued != null) {
        throw LifeMateOfflineQueuedException(
          clientRequestId: queued.clientRequestId,
        );
      }
      rethrow;
    } on http.ClientException {
      if (queued != null) {
        throw LifeMateOfflineQueuedException(
          clientRequestId: queued.clientRequestId,
        );
      }
      rethrow;
    }
  }

  Future<int> flushPending() async {
    if (_flushing || _closed) return 0;
    final startingAccountId = _accountId()?.trim();
    if (startingAccountId == null || startingAccountId.isEmpty) return 0;

    _flushing = true;
    var synced = 0;
    try {
      List<LifeMateQueuedMutation> pending;
      try {
        pending = await _queue.pendingForAccount(startingAccountId);
      } catch (_) {
        return 0;
      }

      for (final mutation in pending) {
        final currentAccountId = _accountId()?.trim();
        final token = _accessToken()?.trim();
        if (currentAccountId != startingAccountId ||
            token == null ||
            token.isEmpty) {
          break;
        }

        final uri = Uri.tryParse(mutation.uri);
        if (uri == null ||
            !_isAllowedPath(uri.path) ||
            !_isCurrentApiUri(uri)) {
          await _bestEffort(() => _queue.remove(mutation.id));
          continue;
        }

        final replay = http.Request(mutation.method, uri)
          ..headers.addAll({
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
            'X-LifeMate-Replay': '1',
          })
          ..body = mutation.body;
        try {
          final response = await _inner.send(replay).timeout(_transportTimeout);
          await response.stream.drain<void>();
          if (_accountId()?.trim() != startingAccountId) break;

          if (_isSuccess(response.statusCode)) {
            await _bestEffort(() => _queue.remove(mutation.id));
            synced++;
            continue;
          }
          if (_isTerminalClientFailure(response.statusCode)) {
            await _bestEffort(() => _queue.remove(mutation.id));
            continue;
          }
          break;
        } on TimeoutException {
          break;
        } on http.ClientException {
          break;
        }
      }
    } finally {
      _flushing = false;
    }
    return synced;
  }

  Future<List<LifeMateQueuedMutation>> pendingMutations() async {
    final accountId = _accountId()?.trim();
    if (accountId == null || accountId.isEmpty) {
      return const <LifeMateQueuedMutation>[];
    }
    try {
      return await _queue.pendingForAccount(accountId);
    } catch (_) {
      return const <LifeMateQueuedMutation>[];
    }
  }

  Future<int> pendingCount() async => (await pendingMutations()).length;

  Future<_DurableCandidate?> _durableCandidate(http.BaseRequest request) async {
    if (request.method != 'POST' ||
        !_isAllowedPath(request.url.path) ||
        !_isCurrentApiUri(request.url)) {
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

  bool _isAllowedPath(String path) => _doseReportPath.hasMatch(path);

  bool _isCurrentApiUri(Uri uri) {
    final sameOrigin =
        uri.scheme.toLowerCase() == _apiBaseUri.scheme.toLowerCase() &&
        uri.host.toLowerCase() == _apiBaseUri.host.toLowerCase() &&
        uri.port == _apiBaseUri.port;
    if (!sameOrigin) return false;
    final basePath = _apiBaseUri.path.replaceFirst(RegExp(r'/+$'), '');
    return basePath.isEmpty ||
        uri.path == basePath ||
        uri.path.startsWith('$basePath/');
  }

  static bool _isSuccess(int status) => status >= 200 && status < 300;

  static bool _isTerminalClientFailure(int status) =>
      status >= 400 &&
      status < 500 &&
      status != 401 &&
      status != 408 &&
      status != 429;

  static Future<void> _bestEffort(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {}
  }

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
