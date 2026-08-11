import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Thrown after an idempotent mutation has been persisted locally but could not
/// be sent because the transport is offline/unreachable.
///
/// The caller should tell the user that the action is saved and will be synced,
/// rather than presenting it as a lost/failed action.
class LifeMateOfflineQueuedException implements Exception {
  const LifeMateOfflineQueuedException({required this.clientRequestId});

  final String clientRequestId;

  @override
  String toString() =>
      'LifeMateOfflineQueuedException(clientRequestId: $clientRequestId)';
}

abstract class LifeMateMutationStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class LifeMateSecureMutationStorage implements LifeMateMutationStorage {
  LifeMateSecureMutationStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
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

  LifeMateQueuedMutation withAttemptCount(int value) => LifeMateQueuedMutation(
        id: id,
        accountId: accountId,
        method: method,
        uri: uri,
        body: body,
        clientRequestId: clientRequestId,
        createdAtUtc: createdAtUtc,
        attemptCount: value,
      );

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

/// A deliberately small queue for high-value, explicitly idempotent writes.
///
/// Health/treatment payloads are never written to SharedPreferences/plaintext.
/// Production uses platform encrypted secure storage. The queue is scoped by
/// account, bounded, and TTL-pruned so one signed-in user cannot replay another
/// user's pending actions.
class LifeMateOfflineMutationQueue {
  LifeMateOfflineMutationQueue({
    LifeMateMutationStorage? storage,
    DateTime Function()? now,
    this.maximumItems = 100,
    this.timeToLive = const Duration(days: 7),
  })  : _storage = storage ?? LifeMateSecureMutationStorage(),
        _now = now ?? (() => DateTime.now().toUtc());

  static const storageKey = 'lifemate.offline_mutations.v1';

  final LifeMateMutationStorage _storage;
  final DateTime Function() _now;
  final int maximumItems;
  final Duration timeToLive;

  Future<LifeMateQueuedMutation> enqueue({
    required String accountId,
    required String method,
    required Uri uri,
    required String body,
    required String clientRequestId,
  }) async {
    if (accountId.trim().isEmpty || clientRequestId.trim().isEmpty) {
      throw ArgumentError('Offline mutations require account and request IDs.');
    }

    final values = await _loadAndPrune();
    for (final value in values) {
      if (value.accountId == accountId &&
          value.method == method &&
          value.uri == uri.toString() &&
          value.clientRequestId == clientRequestId) {
        return value;
      }
    }

    if (values.length >= maximumItems) {
      throw StateError(
        'LifeMate offline queue is full; refusing to silently drop an action.',
      );
    }

    final value = LifeMateQueuedMutation(
      id: '$accountId:$clientRequestId',
      accountId: accountId,
      method: method,
      uri: uri.toString(),
      body: body,
      clientRequestId: clientRequestId,
      createdAtUtc: _now(),
      attemptCount: 0,
    );
    values.add(value);
    await _save(values);
    return value;
  }

  Future<List<LifeMateQueuedMutation>> pendingForAccount(
    String accountId,
  ) async {
    final values = await _loadAndPrune();
    return values
        .where((value) => value.accountId == accountId)
        .toList(growable: false)
      ..sort((a, b) => a.createdAtUtc.compareTo(b.createdAtUtc));
  }

  Future<void> remove(String id) async {
    final values = await _loadAndPrune();
    values.removeWhere((value) => value.id == id);
    await _save(values);
  }

  Future<void> markAttempt(String id) async {
    final values = await _loadAndPrune();
    final index = values.indexWhere((value) => value.id == id);
    if (index < 0) return;
    values[index] = values[index].withAttemptCount(
      values[index].attemptCount + 1,
    );
    await _save(values);
  }

  Future<int> pendingCount(String accountId) async =>
      (await pendingForAccount(accountId)).length;

  Future<List<LifeMateQueuedMutation>> _loadAndPrune() async {
    final raw = await _storage.read(storageKey);
    if (raw == null || raw.trim().isEmpty) return <LifeMateQueuedMutation>[];

    List<dynamic> decoded;
    try {
      decoded = jsonDecode(raw) as List<dynamic>;
    } catch (_) {
      // Corrupted encrypted queue metadata must never crash application start.
      // Start clean rather than trying to interpret an untrusted payload.
      await _storage.write(storageKey, '[]');
      return <LifeMateQueuedMutation>[];
    }

    final cutoff = _now().subtract(timeToLive);
    final values = <LifeMateQueuedMutation>[];
    for (final entry in decoded) {
      if (entry is! Map) continue;
      final value = LifeMateQueuedMutation.fromJson(
        Map<String, dynamic>.from(entry),
      );
      if (value.id.isEmpty ||
          value.accountId.isEmpty ||
          value.clientRequestId.isEmpty ||
          !value.createdAtUtc.isAfter(cutoff)) {
        continue;
      }
      values.add(value);
    }
    if (values.length != decoded.length) await _save(values);
    return values;
  }

  Future<void> _save(List<LifeMateQueuedMutation> values) => _storage.write(
        storageKey,
        jsonEncode(values.map((value) => value.toJson()).toList()),
      );
}
