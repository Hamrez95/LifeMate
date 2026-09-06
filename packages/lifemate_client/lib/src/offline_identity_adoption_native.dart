import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:lifemate_core/lifemate_core.dart';

/// Minimal device-protected identity mapping required to reopen an already
/// adopted Account + Person offline namespace after a process restart.
///
/// This is identity metadata only. It does not cache auth/entitlement/sharing
/// authority and must never be used as proof that remote access is still valid.
final class LifeMateOfflineIdentityAdoption {
  LifeMateOfflineIdentityAdoption({
    required String environmentId,
    required String legacyAccountId,
    required String accountId,
    required String personId,
    required DateTime adoptedAtUtc,
  }) : environmentId = _value(environmentId, 'environmentId', 1024),
       legacyAccountId = _value(legacyAccountId, 'legacyAccountId', 256),
       accountId = _value(accountId, 'accountId', 256),
       personId = _value(personId, 'personId', 256),
       adoptedAtUtc = adoptedAtUtc.toUtc();

  final String environmentId;
  final String legacyAccountId;
  final String accountId;
  final String personId;
  final DateTime adoptedAtUtc;

  LifeMateLocalNamespace toLocalNamespace() => LifeMateLocalNamespace(
    environmentId: environmentId,
    accountId: accountId,
    personId: personId,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'environmentId': environmentId,
    'legacyAccountId': legacyAccountId,
    'accountId': accountId,
    'personId': personId,
    'adoptedAtUtc': adoptedAtUtc.toIso8601String(),
  };

  static LifeMateOfflineIdentityAdoption fromJson(Map<String, dynamic> json) {
    final adoptedAt = DateTime.tryParse(json['adoptedAtUtc']?.toString() ?? '');
    if (adoptedAt == null) {
      throw const LifeMateOfflineIdentityAdoptionCorruptionException();
    }
    try {
      return LifeMateOfflineIdentityAdoption(
        environmentId: json['environmentId']?.toString() ?? '',
        legacyAccountId: json['legacyAccountId']?.toString() ?? '',
        accountId: json['accountId']?.toString() ?? '',
        personId: json['personId']?.toString() ?? '',
        adoptedAtUtc: adoptedAt,
      );
    } on ArgumentError {
      throw const LifeMateOfflineIdentityAdoptionCorruptionException();
    }
  }

  static String _value(String value, String field, int maxLength) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized.length > maxLength) {
      throw ArgumentError.value(value, field);
    }
    return normalized;
  }
}

abstract interface class LifeMateOfflineIdentityStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

final class _SecureIdentityStorage implements LifeMateOfflineIdentityStorage {
  _SecureIdentityStorage([FlutterSecureStorage? storage])
    : _storage = storage ?? _defaultStorage;

  static const FlutterSecureStorage _defaultStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      storageNamespace: 'lifemate_offline_identity_v1',
      migrateOnAlgorithmChange: true,
      migrateWithBackup: false,
      resetOnError: false,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Stores all adopted namespace mappings under one fixed secure-storage key so
/// raw account/person identifiers never appear in key names or SQLite selectors.
final class LifeMateOfflineIdentityAdoptionStore {
  LifeMateOfflineIdentityAdoptionStore._(this._storage);

  static const _storageKey = 'lifemate.offline.identity_adoptions.v1';
  static const _payloadVersion = 1;
  static const _maxEntries = 8;

  final LifeMateOfflineIdentityStorage _storage;

  factory LifeMateOfflineIdentityAdoptionStore.secure({
    FlutterSecureStorage? storage,
  }) => LifeMateOfflineIdentityAdoptionStore._(
    _SecureIdentityStorage(storage),
  );

  factory LifeMateOfflineIdentityAdoptionStore.forTesting(
    LifeMateOfflineIdentityStorage storage,
  ) => LifeMateOfflineIdentityAdoptionStore._(storage);

  Future<void> remember({
    required String environmentId,
    required String legacyAccountId,
    required String accountId,
    required String personId,
    DateTime? adoptedAtUtc,
  }) async {
    final next = LifeMateOfflineIdentityAdoption(
      environmentId: environmentId,
      legacyAccountId: legacyAccountId,
      accountId: accountId,
      personId: personId,
      adoptedAtUtc: adoptedAtUtc ?? DateTime.now().toUtc(),
    );
    final entries = await _readAll();
    entries.removeWhere(
      (entry) =>
          entry.environmentId == next.environmentId &&
          entry.legacyAccountId == next.legacyAccountId,
    );
    entries.add(next);
    entries.sort((a, b) => b.adoptedAtUtc.compareTo(a.adoptedAtUtc));
    if (entries.length > _maxEntries) {
      entries.removeRange(_maxEntries, entries.length);
    }
    await _writeAll(entries);
  }

  Future<LifeMateOfflineIdentityAdoption?> lookup({
    required String environmentId,
    required String legacyAccountId,
  }) async {
    final normalizedEnvironment =
        LifeMateOfflineIdentityAdoption._value(environmentId, 'environmentId', 1024);
    final normalizedLegacy =
        LifeMateOfflineIdentityAdoption._value(legacyAccountId, 'legacyAccountId', 256);
    for (final entry in await _readAll()) {
      if (entry.environmentId == normalizedEnvironment &&
          entry.legacyAccountId == normalizedLegacy) {
        return entry;
      }
    }
    return null;
  }

  Future<void> forget({
    required String environmentId,
    required String legacyAccountId,
  }) async {
    final normalizedEnvironment =
        LifeMateOfflineIdentityAdoption._value(environmentId, 'environmentId', 1024);
    final normalizedLegacy =
        LifeMateOfflineIdentityAdoption._value(legacyAccountId, 'legacyAccountId', 256);
    final entries = await _readAll();
    entries.removeWhere(
      (entry) =>
          entry.environmentId == normalizedEnvironment &&
          entry.legacyAccountId == normalizedLegacy,
    );
    if (entries.isEmpty) {
      await _storage.delete(_storageKey);
    } else {
      await _writeAll(entries);
    }
  }

  Future<void> clear() => _storage.delete(_storageKey);

  Future<List<LifeMateOfflineIdentityAdoption>> _readAll() async {
    final encoded = await _storage.read(_storageKey);
    if (encoded == null || encoded.trim().isEmpty) return [];
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic> ||
          decoded['version'] != _payloadVersion ||
          decoded['entries'] is! List<dynamic>) {
        throw const LifeMateOfflineIdentityAdoptionCorruptionException();
      }
      final result = <LifeMateOfflineIdentityAdoption>[];
      for (final raw in decoded['entries'] as List<dynamic>) {
        if (raw is! Map<String, dynamic>) {
          throw const LifeMateOfflineIdentityAdoptionCorruptionException();
        }
        result.add(LifeMateOfflineIdentityAdoption.fromJson(raw));
      }
      if (result.length > _maxEntries) {
        throw const LifeMateOfflineIdentityAdoptionCorruptionException();
      }
      return result;
    } on FormatException {
      throw const LifeMateOfflineIdentityAdoptionCorruptionException();
    }
  }

  Future<void> _writeAll(List<LifeMateOfflineIdentityAdoption> entries) async {
    final encoded = jsonEncode(<String, dynamic>{
      'version': _payloadVersion,
      'entries': entries.map((entry) => entry.toJson()).toList(growable: false),
    });
    await _storage.write(_storageKey, encoded);
    if (await _storage.read(_storageKey) != encoded) {
      throw StateError('LifeMate offline identity adoption write verification failed.');
    }
  }
}

final class LifeMateOfflineIdentityAdoptionCorruptionException
    implements Exception {
  const LifeMateOfflineIdentityAdoptionCorruptionException();

  @override
  String toString() =>
      'LifeMate offline identity adoption metadata is unavailable or malformed.';
}
