import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'lifemate_api_client.dart' show AccessTokenProvider;
import 'offline_mutation_queue.dart';
import 'offline_sync_result.dart';

typedef LifeMateAccountIdProvider = String? Function();
typedef LifeMateReplayDelegate = Future<LifeMateOfflineSyncResult> Function();

class LifeMateDurableHttpClient extends http.BaseClient {
  LifeMateDurableHttpClient({
    required Uri apiBaseUri,
    required AccessTokenProvider accessToken,
    required LifeMateAccountIdProvider accountId,
    LifeMateOfflineMutationQueue? queue,
    http.Client? inner,
    Duration transportTimeout = const Duration(seconds: 18),
  }) : _apiBaseUri = apiBaseUri,
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
  LifeMateReplayDelegate? _replayDelegate;
  bool _deferReplayUntilDelegate = false;
  bool _flushing = false;
  bool _closed = false;

  static final RegExp _doseReportPath = RegExp(
    r'/api/v1/dose-occurrences/[0-9a-f-]{36}/report$',
    caseSensitive: false,
  );

  /// Storage seam used only by the #831 lossless importer. Durable payloads
  /// remain encapsulated by the queue for all product/runtime code.
  LifeMateMutationStorage get migrationStorage => _queue.migrationStorage;

  /// Prevents the transitional account-only queue from replaying before the
  /// server has resolved canonical Account + Person identity. Writes remain
  /// durably captured and are later imported by the shared runtime.
  void deferReplayUntilDelegate() {
    if (_closed) throw StateError('Client is closed.');
    _deferReplayUntilDelegate = true;
  }

  /// Switches replay ownership to the shared Account/Person-scoped runtime.
  /// The legacy queue continues to capture an allow-listed write before its
  /// network attempt until capture itself is moved into lifemate_core.
  void useReplayDelegate(LifeMateReplayDelegate delegate) {
    if (_closed) throw StateError('Client is closed.');
    _replayDelegate = delegate;
  }

  /// Immediately detaches the Account/Person replay runtime after an auth
  /// identity transition. Replay stays deferred until the next authenticated
  /// bootstrap resolves canonical Account + Person and installs a fresh
  /// delegate. Pending encrypted mutations are preserved on disk.
  void isolateReplayDelegate() {
    if (_closed) return;
    _replayDelegate = null;
    _deferReplayUntilDelegate = true;
  }

  bool get _canAutoReplay =>
      !_deferReplayUntilDelegate || _replayDelegate != null;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_closed) throw http.ClientException('Client is closed.', request.url);

    final durable = await _durableCandidate(request);
    if (durable == null) {
      final response = await _inner.send(request);
      if (_isSuccess(response.statusCode) && _canAutoReplay) {
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
          await response.stream.drain<void>();
          throw LifeMateOfflineQueuedException(
            clientRequestId: queued.clientRequestId,
          );
        }
      }
      if (_isSuccess(response.statusCode) && _canAutoReplay) {
        unawaited(flushPending());
      }
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

  Future<int> flushPending() async => (await flushPendingDetailed()).synced;

  /// Replays through the shared runtime once one has been adopted. If replay
  /// has been deferred, account-only actions remain untouched until canonical
  /// Person resolution installs the shared delegate.
  Future<LifeMateOfflineSyncResult> flushPendingDetailed() async {
    final delegate = _replayDelegate;
    if (delegate != null) return delegate();
    if (_deferReplayUntilDelegate) return const LifeMateOfflineSyncResult();
    return _flushLegacyPendingDetailed();
  }

  /// Transitional pre-#831 replay path retained only for callers that have not
  /// opted into canonical Account/Person runtime adoption.
  Future<LifeMateOfflineSyncResult> _flushLegacyPendingDetailed() async {
    if (_flushing || _closed) return const LifeMateOfflineSyncResult();
    final startingAccountId = _accountId()?.trim();
    if (startingAccountId == null || startingAccountId.isEmpty) {
      return const LifeMateOfflineSyncResult();
    }

    _flushing = true;
    var replayed = 0;
    var conflicts = 0;
    var terminalRejected = 0;
    var retainedForRetry = 0;
    var removedUnsafe = 0;
    try {
      List<LifeMateQueuedMutation> pending;
      try {
        pending = await _queue.pendingForAccount(startingAccountId);
      } catch (_) {
        return const LifeMateOfflineSyncResult();
      }

      for (final mutation in pending) {
        final currentAccountId = _accountId()?.trim();
        final token = _accessToken()?.trim();
        if (currentAccountId != startingAccountId ||
            token == null ||
            token.isEmpty) {
          retainedForRetry += 1;
          break;
        }

        final uri = Uri.tryParse(mutation.uri);
        if (uri == null ||
            !_isAllowedPath(uri.path) ||
            !_isCurrentApiUri(uri)) {
          await _bestEffort(() => _queue.remove(mutation.id));
          removedUnsafe += 1;
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
          if (_accountId()?.trim() != startingAccountId) {
            retainedForRetry += 1;
            break;
          }

          if (_isSuccess(response.statusCode)) {
            await _bestEffort(() => _queue.remove(mutation.id));
            replayed += 1;
            continue;
          }
          if (response.statusCode == 409) {
            await _bestEffort(() => _queue.remove(mutation.id));
            conflicts += 1;
            continue;
          }
          if (_isTerminalClientFailure(response.statusCode)) {
            await _bestEffort(() => _queue.remove(mutation.id));
            terminalRejected += 1;
            continue;
          }
          retainedForRetry += 1;
          break;
        } on TimeoutException {
          retainedForRetry += 1;
          break;
        } on http.ClientException {
          retainedForRetry += 1;
          break;
        }
      }
    } finally {
      _flushing = false;
    }

    var remaining = 0;
    try {
      remaining = await _queue.pendingCount(startingAccountId);
    } catch (_) {
      remaining = retainedForRetry > 0 ? 1 : 0;
    }
    return LifeMateOfflineSyncResult(
      replayed: replayed,
      conflicts: conflicts,
      terminalRejected: terminalRejected,
      retainedForRetry: retainedForRetry,
      removedUnsafe: removedUnsafe,
      pendingRemaining: remaining,
    );
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
    if (accountId == null || accountId.isEmpty) return null;
    final bodyBytes = await request.finalize().toBytes();
    final body = utf8.decode(bodyBytes);
    final clientRequestId = _readClientRequestId(body);
    if (clientRequestId == null) return null;
    return _DurableCandidate(
      accountId: accountId,
      body: body,
      bodyBytes: bodyBytes,
      clientRequestId: clientRequestId,
    );
  }

  bool _isAllowedPath(String path) => _doseReportPath.hasMatch(path);

  bool _isCurrentApiUri(Uri uri) =>
      uri.scheme == _apiBaseUri.scheme &&
      uri.host == _apiBaseUri.host &&
      uri.port == _apiBaseUri.port;

  String? _readClientRequestId(String body) {
    dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    final value = decoded['clientRequestId']?.toString().trim();
    return value == null || value.isEmpty ? null : value;
  }

  static http.Request _copyRequest(http.BaseRequest source, List<int> bodyBytes) {
    final request = http.Request(source.method, source.url)
      ..headers.addAll(source.headers)
      ..followRedirects = source.followRedirects
      ..maxRedirects = source.maxRedirects
      ..persistentConnection = source.persistentConnection
      ..bodyBytes = bodyBytes;
    return request;
  }

  static bool _isSuccess(int statusCode) => statusCode >= 200 && statusCode < 300;

  static bool _isTerminalClientFailure(int statusCode) =>
      statusCode == 400 ||
      statusCode == 403 ||
      statusCode == 404 ||
      statusCode == 409 ||
      statusCode == 410 ||
      statusCode == 422;

  static Future<void> _bestEffort(Future<void> Function() operation) async {
    try {
      await operation();
    } catch (_) {
      // Queue cleanup must never hide the response that the user already got.
    }
  }

  @override
  void close() {
    _closed = true;
    _replayDelegate = null;
    _inner.close();
    super.close();
  }
}

final class _DurableCandidate {
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
