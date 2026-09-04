import 'dart:convert';

import 'package:lifemate_core/lifemate_core.dart';

import 'offline_mutation_queue.dart';

/// Imports the pre-#831 secure-storage dose queue into the shared encrypted
/// local outbox without deleting an accepted legacy action until the structured
/// copy has been durably persisted.
final class LifeMateLegacyMutationImporter {
  LifeMateLegacyMutationImporter({
    required LifeMateLocalMutationOutbox outbox,
    required Uri apiBaseUri,
    LifeMateMutationStorage? legacyStorage,
  }) : _legacyStorage = legacyStorage ?? LifeMateSecureMutationStorage(),
       _outbox = outbox,
       _apiBaseUri = apiBaseUri;

  static const _legacyItemPrefix = 'lifemate.offline_mutation.v2.';

  final LifeMateMutationStorage _legacyStorage;
  final LifeMateLocalMutationOutbox _outbox;
  final Uri _apiBaseUri;

  static final RegExp _doseReportPath = RegExp(
    r'^/api/v1/dose-occurrences/([0-9a-f-]{36})/report$',
    caseSensitive: false,
  );

  /// Returns the number of legacy records safely imported and removed.
  ///
  /// Migration intentionally reads the legacy secure-storage records directly
  /// instead of calling [LifeMateOfflineMutationQueue.pendingForAccount]. The
  /// old queue prunes by a seven-day TTL; #831 must not silently lose an action
  /// that was previously accepted just because migration happened later.
  /// Invalid, foreign-account or origin-mismatched records are retained for
  /// explicit handling.
  Future<int> importPending({
    required LifeMateLocalNamespace namespace,
    required String timeZone,
  }) async {
    final accountId = namespace.accountId.trim();
    final zone = timeZone.trim();
    if (accountId.isEmpty || zone.isEmpty) {
      throw ArgumentError('Account and timezone are required for migration.');
    }

    final raw = await _legacyStorage.readAll();
    final pending = <({String storageKey, LifeMateQueuedMutation mutation})>[];
    for (final entry in raw.entries) {
      if (!entry.key.startsWith(_legacyItemPrefix)) continue;
      final decoded = _decodeLegacy(entry.value);
      if (decoded == null || decoded.accountId != accountId) continue;
      pending.add((storageKey: entry.key, mutation: decoded));
    }
    pending.sort((a, b) {
      final byDate = a.mutation.createdAtUtc.compareTo(b.mutation.createdAtUtc);
      return byDate != 0 ? byDate : a.mutation.id.compareTo(b.mutation.id);
    });

    var imported = 0;
    for (final item in pending) {
      final converted = _convert(item.mutation, zone);
      if (converted == null) continue;

      await _outbox.enqueue(namespace: namespace, mutation: converted);
      await _legacyStorage.delete(item.storageKey);
      imported += 1;
    }
    return imported;
  }

  LifeMateQueuedMutation? _decodeLegacy(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final mutation = LifeMateQueuedMutation.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      if (mutation.id.isEmpty ||
          mutation.accountId.isEmpty ||
          mutation.clientRequestId.isEmpty ||
          mutation.id != '${mutation.accountId}:${mutation.clientRequestId}' ||
          !mutation.createdAtUtc.isUtc) {
        return null;
      }
      return mutation;
    } catch (_) {
      return null;
    }
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
