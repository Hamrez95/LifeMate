import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class LifeMateOfflineQueuedException implements Exception {
  const LifeMateOfflineQueuedException({required this.clientRequestId});

  final String clientRequestId;

  @override
  String toString() =>
      'LifeMateOfflineQueuedException(clientRequestId: $clientRequestId)';
}

abstract class LifeMateMutationStorage {
  Future<String?> read(String key);
  Future<Map<String, String>> readAll();
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class LifeMateSecureMutationStorage implements LifeMateMutationStorage {
  LifeMateSecureMutationStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<Map<String, String>> readAll() => _storage.readAll();

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class LifeMateQueuedMutation {
  const LifeMateQueuedMutation({
    required this.id,
    required this.accountId,
    required this.method,
    required this.uri,
    required this.body,
    required this.clientRequestId,
    required this.createdAtUtc,
  });

  factory LifeMateQueuedMutation.fromJson(Map<String, dynamic> json) {
    return LifeMateQueuedMutation(
      id: json['id']?.toString() ?? '',
      accountId: json['accountId']?.toString() ?? '',
      method: json['method']?.toString() ?? '',
      uri: json['uri']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      clientRequestId: json['clientRequestId']?.toString() ?? '',
      createdAtUtc:
          DateTime.tryParse(json['createdAtUtc']?.toString() ?? '')?.toUtc() ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  final String id;
  final String accountId;
  final String method;
  final String uri;
  final String body;
  final String clientRequestId;
  final DateTime createdAtUtc;

  Map<String, dynamic> toJson() => {
        'id': id,
        'accountId': accountId,
        'method': method,
        'uri': uri,
        'body': body,
        'clientRequestId': clientRequestId,
        'createdAtUtc': createdAtUtc.toIso8601String(),
      };
}

/// Encrypted, account-scoped queue for the very small allowlist of writes whose
/// server contract is explicitly idempotent. Authentication tokens are never
/// persisted with the healthcare payload.
///
/// Each mutation has an independent deterministic secure-storage key so the
/// foreground app and Android widget callback cannot overwrite a shared list.
class LifeMateOfflineMutationQueue {
  LifeMateOfflineMutationQueue({
    LifeMateMutationStorage? storage,
    DateTime Function()? now,
    this.maximumItems = 100,
    this.timeToLive = const Duration(days: 7),
  })  : _storage = storage ?? LifeMateSecureMutationStorage(),
        _now = now ?? (() => DateTime.now().toUtc());

  static const _itemPrefix = 'lifemate.offline_mutation.v2.';

  final LifeMateMutationStorage _storage;
  final DateTime Function() _now;
  final int maximumItems;
  final Duration timeToLive;
  Future<void> _tail = Future<void>.value();

  /// Transitional #831 migration seam. New runtime code must not use this to
  /// inspect health payloads; it exists only so the shared importer can move
  /// already-accepted legacy records without creating a second storage owner.
  LifeMateMutationStorage get migrationStorage => _storage;

  Future<LifeMateQueuedMutation> enqueue({
    required String accountId,
    required String method,
    required Uri uri,
    required String body,
    required String clientRequestId,
  }) =>
      _serialized(() async {
        final normalizedAccount = accountId.trim();
        final normalizedRequest = clientRequestId.trim();
        if (normalizedAccount.isEmpty || normalizedRequest.isEmpty) {
          throw ArgumentError(
              'Offline mutations require account and request IDs.');
        }

        final id = '$normalizedAccount:$normalizedRequest';
        final key = _itemKey(id);
        final existing = await _readValidItemUnlocked(key);
        if (existing != null) return existing;

        final before = await _loadAndPruneUnlocked();
        if (before.length >= maximumItems) {
          throw StateError(
            'LifeMate offline queue is full; refusing to silently drop an action.',
          );
        }

        final value = LifeMateQueuedMutation(
          id: id,
          accountId: normalizedAccount,
          method: method,
          uri: uri.toString(),
          body: body,
          clientRequestId: normalizedRequest,
          createdAtUtc: _now(),
        );
        await _storage.write(key, jsonEncode(value.toJson()));

        // Cross-isolate writers can both observe capacity before either writes.
        // Recheck after our write and remove only our unacknowledged item on
        // overflow; never evict an older action whose caller was told it persisted.
        final after = await _loadAndPruneUnlocked();
        if (after.length > maximumItems) {
          await _storage.delete(key);
          throw StateError(
            'LifeMate offline queue is full; refusing to silently drop an action.',
          );
        }
        return value;
      });

  Future<List<LifeMateQueuedMutation>> pendingForAccount(String accountId) =>
      _serialized(() async {
        final values = await _loadAndPruneUnlocked();
        final result = values
            .where((value) => value.accountId == accountId)
            .toList(growable: false);
        result.sort((a, b) {
          final byDate = a.createdAtUtc.compareTo(b.createdAtUtc);
          return byDate != 0 ? byDate : a.id.compareTo(b.id);
        });
        return result;
      });

  Future<void> remove(String id) =>
      _serialized(() => _storage.delete(_itemKey(id)));

  Future<int> pendingCount(String accountId) async =>
      (await pendingForAccount(accountId)).length;

  Future<T> _serialized<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _tail = _tail.catchError((_) {}).then<void>((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<List<LifeMateQueuedMutation>> _loadAndPruneUnlocked() async {
    final all = await _storage.readAll();
    final cutoff = _now().subtract(timeToLive);
    final values = <LifeMateQueuedMutation>[];

    for (final entry in all.entries) {
      if (!entry.key.startsWith(_itemPrefix)) continue;
      final value = _decode(entry.value);
      if (value == null || !_isValid(value, cutoff)) {
        await _storage.delete(entry.key);
        continue;
      }
      values.add(value);
    }
    return values;
  }

  Future<LifeMateQueuedMutation?> _readValidItemUnlocked(String key) async {
    final raw = await _storage.read(key);
    if (raw == null || raw.trim().isEmpty) return null;
    final value = _decode(raw);
    final cutoff = _now().subtract(timeToLive);
    if (value == null || !_isValid(value, cutoff)) {
      await _storage.delete(key);
      return null;
    }
    return value;
  }

  LifeMateQueuedMutation? _decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final value = LifeMateQueuedMutation.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      return value.id.isEmpty ||
              value.accountId.isEmpty ||
              value.clientRequestId.isEmpty ||
              value.method.toUpperCase() != 'POST' ||
              value.uri.isEmpty ||
              !value.createdAtUtc.isUtc
          ? null
          : value;
    } catch (_) {
      return null;
    }
  }

  bool _isValid(LifeMateQueuedMutation value, DateTime cutoff) =>
      value.id == '${value.accountId}:${value.clientRequestId}' &&
      !value.createdAtUtc.isBefore(cutoff);

  static String _itemKey(String id) => '$_itemPrefix$id';
}
