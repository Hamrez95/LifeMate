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
    required this.attemptCount,
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
      attemptCount: int.tryParse(json['attemptCount']?.toString() ?? '') ?? 0,
    );
  }

  final String id;
  final String accountId;
  final String method;
  final String uri;
  final String body;
  final String clientRequestId;
  final DateTime createdAtUtc;
  final int attemptCount;

  Map<String, dynamic> toJson() => {
        'id': id,
        'accountId': accountId,
        'method': method,
        'uri': uri,
        'body': body,
        'clientRequestId': clientRequestId,
        'createdAtUtc': createdAtUtc.toIso8601String(),
        'attemptCount': attemptCount,
      };
}

/// Encrypted queue for the small allowlist of explicitly-idempotent writes.
///
/// Each mutation is stored under its own deterministic secure-storage key.
/// This matters because the foreground app and Android home-widget callback can
/// run with different [LifeMateOfflineMutationQueue] instances (and isolates).
/// A single JSON-list key would require a cross-process compare-and-swap that
/// flutter_secure_storage does not expose; independent item keys avoid the lost
/// update entirely. The existing per-instance tail still orders operations made
/// through one object, while distinct instances never overwrite each other's
/// mutations.
class LifeMateOfflineMutationQueue {
  LifeMateOfflineMutationQueue({
    LifeMateMutationStorage? storage,
    DateTime Function()? now,
    this.maximumItems = 100,
    this.timeToLive = const Duration(days: 7),
  })  : _storage = storage ?? LifeMateSecureMutationStorage(),
        _now = now ?? (() => DateTime.now().toUtc());

  /// Legacy v1 list key retained only for one-way migration.
  static const storageKey = 'lifemate.offline_mutations.v1';
  static const _itemPrefix = 'lifemate.offline_mutation.v2.';

  final LifeMateMutationStorage _storage;
  final DateTime Function() _now;
  final int maximumItems;
  final Duration timeToLive;
  Future<void> _tail = Future<void>.value();
  bool _legacyMigrationAttempted = false;

  Future<LifeMateQueuedMutation> enqueue({
    required String accountId,
    required String method,
    required Uri uri,
    required String body,
    required String clientRequestId,
  }) => _serialized(() async {
        final normalizedAccount = accountId.trim();
        final normalizedRequest = clientRequestId.trim();
        if (normalizedAccount.isEmpty || normalizedRequest.isEmpty) {
          throw ArgumentError(
            'Offline mutations require account and request IDs.',
          );
        }

        await _migrateLegacyUnlocked();
        final id = '$normalizedAccount:$normalizedRequest';
        final key = _itemKey(id);
        final existing = await _readValidItemUnlocked(key);
        if (existing != null) {
          // The deterministic key makes the same idempotency request naturally
          // converge even when two queue instances enqueue it concurrently.
          return existing;
        }

        final values = await _loadAndPruneUnlocked();
        if (values.length >= maximumItems) {
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
          attemptCount: 0,
        );
        await _storage.write(key, jsonEncode(value.toJson()));
        return value;
      });

  Future<List<LifeMateQueuedMutation>> pendingForAccount(String accountId) =>
      _serialized(() async {
        await _migrateLegacyUnlocked();
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

  Future<void> remove(String id) => _serialized(() async {
        await _migrateLegacyUnlocked();
        await _storage.delete(_itemKey(id));
      });

  /// Attempt counters were diagnostic only and were never used to decide
  /// replay. Persisting them would reintroduce a read-modify-write race where a
  /// failed duplicate replay could resurrect an item that another isolate had
  /// already successfully removed. Keep the queue append/remove-only instead.
  Future<void> markAttempt(String id) async {}

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

  Future<void> _migrateLegacyUnlocked() async {
    if (_legacyMigrationAttempted) return;
    _legacyMigrationAttempted = true;

    final raw = await _storage.read(storageKey);
    if (raw == null || raw.trim().isEmpty) return;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        final cutoff = _now().subtract(timeToLive);
        for (final entry in decoded) {
          if (entry is! Map) continue;
          final value = LifeMateQueuedMutation.fromJson(
            Map<String, dynamic>.from(entry),
          );
          if (!_isValid(value, cutoff)) continue;
          final key = _itemKey(value.id);
          if (await _storage.read(key) == null) {
            await _storage.write(key, jsonEncode(value.toJson()));
          }
        }
      }
    } catch (_) {
      // Corrupt legacy data is discarded rather than copied into v2.
    } finally {
      await _storage.delete(storageKey);
    }
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
      return LifeMateQueuedMutation.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  bool _isValid(LifeMateQueuedMutation value, DateTime cutoff) =>
      value.id.isNotEmpty &&
      value.accountId.isNotEmpty &&
      value.clientRequestId.isNotEmpty &&
      value.createdAtUtc.isAfter(cutoff);

  static String _itemKey(String id) {
    final encoded = base64Url.encode(utf8.encode(id)).replaceAll('=', '');
    return '$_itemPrefix$encoded';
  }
}
