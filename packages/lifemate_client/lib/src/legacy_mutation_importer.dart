import 'dart:convert';

import 'package:lifemate_core/lifemate_core.dart';

import 'offline_mutation_queue.dart';

/// Imports the pre-#831 secure-storage dose queue into the shared encrypted
/// local outbox without deleting an accepted legacy action until the structured
/// copy has been durably persisted.
final class LifeMateLegacyMutationImporter {
  LifeMateLegacyMutationImporter({
    required LifeMateOfflineMutationQueue legacyQueue,
    required LifeMateLocalMutationOutbox outbox,
    required Uri apiBaseUri,
  }) : _legacyQueue = legacyQueue,
       _outbox = outbox,
       _apiBaseUri = apiBaseUri;

  final LifeMateOfflineMutationQueue _legacyQueue;
  final LifeMateLocalMutationOutbox _outbox;
  final Uri _apiBaseUri;

  static final RegExp _doseReportPath = RegExp(
    r'^/api/v1/dose-occurrences/([0-9a-f-]{36})/report$',
    caseSensitive: false,
  );

  /// Returns the number of legacy records safely imported and removed.
  ///
  /// Invalid or origin-mismatched records are retained in the legacy queue so
  /// migration never silently discards an action the UI previously accepted.
  Future<int> importPending({
    required LifeMateLocalNamespace namespace,
    required String timeZone,
  }) async {
    final accountId = namespace.accountId.trim();
    final zone = timeZone.trim();
    if (accountId.isEmpty || zone.isEmpty) {
      throw ArgumentError('Account and timezone are required for migration.');
    }

    final pending = await _legacyQueue.pendingForAccount(accountId);
    var imported = 0;
    for (final legacy in pending) {
      final converted = _convert(legacy, zone);
      if (converted == null) continue;

      await _outbox.enqueue(namespace: namespace, mutation: converted);
      await _legacyQueue.remove(legacy.id);
      imported += 1;
    }
    return imported;
  }

  LifeMateDurableMutation? _convert(
    LifeMateQueuedMutation legacy,
    String timeZone,
  ) {
    if (legacy.accountId.trim().isEmpty ||
        legacy.clientRequestId.trim().isEmpty ||
        legacy.method.toUpperCase() != 'POST') {
      return null;
    }

    final uri = Uri.tryParse(legacy.uri);
    if (uri == null || !_isCurrentApiUri(uri)) return null;
    final match = _doseReportPath.firstMatch(uri.path);
    if (match == null) return null;

    dynamic decoded;
    try {
      decoded = jsonDecode(legacy.body);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    final payload = <String, dynamic>{
      for (final entry in decoded.entries) entry.key.toString(): entry.value,
    };
    final requestId = payload['clientRequestId']?.toString().trim();
    if (requestId == null || requestId != legacy.clientRequestId.trim()) {
      return null;
    }

    return LifeMateDurableMutation(
      mutationId: legacy.clientRequestId,
      domain: LifeMateMutationDomain.adherence,
      sourceKey: match.group(1)!,
      method: legacy.method,
      endpointPath: uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path,
      payload: payload,
      createdAtUtc: legacy.createdAtUtc.toUtc(),
      timeZone: timeZone,
      expectedRevision: payload['expectedVersion']?.toString(),
    );
  }

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
}
