import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

/// Bounded local domains that may participate in LifeMate's offline owner
/// experience. Adding a new value is an explicit platform decision rather than
/// allowing arbitrary feature code to dump health JSON into the local store.
enum LifeMateLocalProjectionDomain {
  treatmentPlan('treatment_plan'),
  treatmentOccurrence('treatment_occurrence'),
  careEvent('care_event'),
  womenHealthCycle('women_health_cycle'),
  pregnancySnapshot('pregnancy_snapshot'),
  pregnancyContent('pregnancy_content'),
  healthObservation('health_observation'),
  pendingMutation('pending_mutation'),
  notificationSchedule('notification_schedule');

  const LifeMateLocalProjectionDomain(this.wireName);

  final String wireName;
}

/// Namespaces protected local health state by deployment environment, account,
/// and Person. Raw identifiers are never written to the SQLite file.
final class LifeMateLocalNamespace {
  LifeMateLocalNamespace({
    required String environmentId,
    required String accountId,
    required String personId,
  })  : environmentId = _requireValue(environmentId, 'environmentId'),
        accountId = _requireValue(accountId, 'accountId'),
        personId = _requireValue(personId, 'personId');

  final String environmentId;
  final String accountId;
  final String personId;

  static String _requireValue(String value, String field) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(value, field, '$field must not be empty.');
    }
    return normalized;
  }
}

/// Decrypted projection returned to a trusted product module.
final class LifeMateLocalProjectionRecord {
  const LifeMateLocalProjectionRecord({
    required this.domain,
    required this.recordKey,
    required this.payload,
    required this.storedAtUtc,
    this.sourceRevision,
    this.sourceUpdatedAtUtc,
    this.syncCursor,
    this.contentVersion,
    this.ruleVersion,
  });

  final LifeMateLocalProjectionDomain domain;
  final String recordKey;
  final Map<String, dynamic> payload;
  final DateTime storedAtUtc;
  final String? sourceRevision;
  final DateTime? sourceUpdatedAtUtc;
  final String? syncCursor;
  final String? contentVersion;
  final String? ruleVersion;
}

abstract interface class LifeMateLocalKeyStore {
  Future<List<int>?> readKey();
  Future<List<int>> createKey();
  Future<void> deleteKey();
}

/// Stores only the random local-data master key in the platform protected
/// keystore/keychain. Health payloads themselves are not stored here.
final class LifeMateSecureLocalKeyStore implements LifeMateLocalKeyStore {
  LifeMateSecureLocalKeyStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _keyName = 'lifemate.local_health.master_key.v1';

  final FlutterSecureStorage _storage;

  @override
  Future<List<int>?> readKey() async {
    final encoded = await _storage.read(key: _keyName);
    if (encoded == null || encoded.trim().isEmpty) return null;
    try {
      final decoded = base64Url.decode(encoded);
      if (decoded.length != LifeMateLocalHealthStore.keyLengthBytes) {
        throw const LifeMateLocalStoreKeyUnavailableException();
      }
      return decoded;
    } on FormatException {
      throw const LifeMateLocalStoreKeyUnavailableException();
    }
  }

  @override
  Future<List<int>> createKey() async {
    final secret = await AesGcm.with256bits().newSecretKey();
    final generated = await secret.extractBytes();
    secret.destroy();
    if (generated.length != LifeMateLocalHealthStore.keyLengthBytes) {
      throw const LifeMateLocalStoreKeyUnavailableException();
    }
    await _storage.write(key: _keyName, value: base64Url.encode(generated));

    // Read back the protected value instead of assuming the write succeeded.
    // This also makes storage failures visible rather than silently continuing
    // with an unpersisted key.
    final persisted = await readKey();
    if (persisted == null) {
      throw const LifeMateLocalStoreKeyUnavailableException();
    }
    return persisted;
  }

  @override
  Future<void> deleteKey() => _storage.delete(key: _keyName);
}

final class LifeMateLocalStoreKeyUnavailableException implements Exception {
  const LifeMateLocalStoreKeyUnavailableException();

  @override
  String toString() =>
      'LifeMate local health data key is unavailable; protected data was not reset.';
}

final class LifeMateLocalStoreCorruptionException implements Exception {
  const LifeMateLocalStoreCorruptionException();

  @override
  String toString() =>
      'LifeMate local health data could not be authenticated or decoded.';
}

final class LifeMateLocalStoreSchemaException implements Exception {
  const LifeMateLocalStoreSchemaException(this.message);

  final String message;

  @override
  String toString() => 'LifeMateLocalStoreSchemaException: $message';
}

/// Shared protected local health projection foundation.
///
/// Security model:
/// - SQLite provides transactional structured persistence and migrations.
/// - Every health payload and its sensitive metadata are AES-256-GCM encrypted.
/// - Environment/account/person/domain/record selectors stored in SQLite are
///   deterministic HMAC tokens keyed by the protected master key, so a copied
///   database cannot trivially reveal raw identifiers or that a row represents
///   pregnancy/cycle/medication data.
/// - The random master key lives only in platform protected secure storage.
/// - If the SQLite file exists but the key is missing, opening fails visibly;
///   the store never generates a replacement key and silently discards data.
///
/// The local database is a rebuildable owner projection plus pending local
/// mutations, not an independent canonical backend.
final class LifeMateLocalHealthStore {
  LifeMateLocalHealthStore._({
    required Database database,
    required List<int> keyBytes,
    required this.databaseFilePath,
    DateTime Function()? now,
  })  : _database = database,
        _keyBytes = Uint8List.fromList(keyBytes),
        _now = now ?? (() => DateTime.now().toUtc()) {
    if (_keyBytes.length != keyLengthBytes) {
      throw const LifeMateLocalStoreKeyUnavailableException();
    }
    _secretKey = SecretKey(_keyBytes);
    _migrateAndVerify();
  }

  static const int schemaVersion = 1;
  static const int keyLengthBytes = 32;
  static const int maximumPlaintextEnvelopeBytes = 256 * 1024;
  static const String defaultDatabaseFileName = 'lifemate_health_local_v1.sqlite3';

  final Database _database;
  final Uint8List _keyBytes;
  final DateTime Function() _now;
  final String? databaseFilePath;
  late final SecretKey _secretKey;
  final AesGcm _cipher = AesGcm.with256bits();
  bool _closed = false;

  /// Opens the native app-local database. Call this during the main app
  /// bootstrap before spawning background isolates that need local health data.
  static Future<LifeMateLocalHealthStore> openDefault({
    LifeMateLocalKeyStore? keyStore,
    DateTime Function()? now,
  }) async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory(p.join(support.path, 'lifemate'));
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }
    return openAtPath(
      p.join(directory.path, defaultDatabaseFileName),
      keyStore: keyStore,
      now: now,
    );
  }

  /// Host/test seam for a caller-controlled native database path.
  static Future<LifeMateLocalHealthStore> openAtPath(
    String path, {
    LifeMateLocalKeyStore? keyStore,
    DateTime Function()? now,
  }) async {
    final normalizedPath = path.trim();
    if (normalizedPath.isEmpty) {
      throw ArgumentError.value(path, 'path', 'Database path must not be empty.');
    }

    final file = File(normalizedPath);
    final hasExistingDatabase = file.existsSync() && file.lengthSync() > 0;
    final store = keyStore ?? LifeMateSecureLocalKeyStore();
    var key = await store.readKey();
    if (key == null) {
      if (hasExistingDatabase) {
        throw const LifeMateLocalStoreKeyUnavailableException();
      }
      key = await store.createKey();
    }
    if (key.length != keyLengthBytes) {
      throw const LifeMateLocalStoreKeyUnavailableException();
    }

    final parent = file.parent;
    if (!parent.existsSync()) parent.createSync(recursive: true);
    final database = sqlite3.open(normalizedPath);
    try {
      return LifeMateLocalHealthStore._(
        database: database,
        keyBytes: key,
        databaseFilePath: normalizedPath,
        now: now,
      );
    } catch (_) {
      database.dispose();
      rethrow;
    }
  }

  /// In-memory/external-database constructor for deterministic unit tests.
  factory LifeMateLocalHealthStore.forTesting({
    required Database database,
    required List<int> keyBytes,
    DateTime Function()? now,
  }) {
    return LifeMateLocalHealthStore._(
      database: database,
      keyBytes: keyBytes,
      databaseFilePath: null,
      now: now,
    );
  }

  Future<void> putProjection({
    required LifeMateLocalNamespace namespace,
    required LifeMateLocalProjectionDomain domain,
    required String recordKey,
    required Map<String, dynamic> payload,
    String? sourceRevision,
    DateTime? sourceUpdatedAtUtc,
    String? syncCursor,
    String? contentVersion,
    String? ruleVersion,
  }) async {
    _ensureOpen();
    final normalizedRecordKey = _requireRecordKey(recordKey);
    final selectors = _selectors(namespace, domain, normalizedRecordKey);
    final storedAt = _now();
    final envelope = <String, dynamic>{
      'version': 1,
      'namespaceToken': selectors.namespaceToken,
      'domainToken': selectors.domainToken,
      'recordToken': selectors.recordToken,
      'domain': domain.wireName,
      'recordKey': normalizedRecordKey,
      'payload': payload,
      'sourceRevision': _nullableTrim(sourceRevision),
      'sourceUpdatedAtUtc': sourceUpdatedAtUtc?.toUtc().toIso8601String(),
      'syncCursor': _nullableTrim(syncCursor),
      'contentVersion': _nullableTrim(contentVersion),
      'ruleVersion': _nullableTrim(ruleVersion),
      'storedAtUtc': storedAt.toIso8601String(),
    };

    final cleartext = utf8.encode(jsonEncode(envelope));
    if (cleartext.length > maximumPlaintextEnvelopeBytes) {
      throw ArgumentError(
        'Local health projection exceeds the bounded payload limit.',
      );
    }

    final aad = _aad(selectors);
    final secretBox = await _cipher.encrypt(
      cleartext,
      secretKey: _secretKey,
      aad: aad,
    );

    _database.execute(
      '''
      INSERT INTO lifemate_local_projection_records (
        environment_token,
        account_token,
        namespace_token,
        domain_token,
        record_token,
        ciphertext,
        nonce,
        mac
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(namespace_token, domain_token, record_token)
      DO UPDATE SET
        environment_token = excluded.environment_token,
        account_token = excluded.account_token,
        ciphertext = excluded.ciphertext,
        nonce = excluded.nonce,
        mac = excluded.mac
      ''',
      <Object?>[
        selectors.environmentToken,
        selectors.accountToken,
        selectors.namespaceToken,
        selectors.domainToken,
        selectors.recordToken,
        Uint8List.fromList(secretBox.cipherText),
        Uint8List.fromList(secretBox.nonce),
        Uint8List.fromList(secretBox.mac.bytes),
      ],
    );
  }

  Future<LifeMateLocalProjectionRecord?> readProjection({
    required LifeMateLocalNamespace namespace,
    required LifeMateLocalProjectionDomain domain,
    required String recordKey,
  }) async {
    _ensureOpen();
    final normalizedRecordKey = _requireRecordKey(recordKey);
    final selectors = _selectors(namespace, domain, normalizedRecordKey);
    final rows = _database.select(
      '''
      SELECT environment_token, account_token, namespace_token, domain_token,
             record_token, ciphertext, nonce, mac
      FROM lifemate_local_projection_records
      WHERE namespace_token = ? AND domain_token = ? AND record_token = ?
      LIMIT 1
      ''',
      <Object?>[
        selectors.namespaceToken,
        selectors.domainToken,
        selectors.recordToken,
      ],
    );
    if (rows.isEmpty) return null;
    return _decryptRow(rows.first, expectedDomain: domain, selectors: selectors);
  }

  Future<List<LifeMateLocalProjectionRecord>> listDomain({
    required LifeMateLocalNamespace namespace,
    required LifeMateLocalProjectionDomain domain,
  }) async {
    _ensureOpen();
    final namespaceSelectors = _namespaceSelectors(namespace);
    final domainToken = _token('domain', <String>[domain.wireName]);
    final rows = _database.select(
      '''
      SELECT environment_token, account_token, namespace_token, domain_token,
             record_token, ciphertext, nonce, mac
      FROM lifemate_local_projection_records
      WHERE namespace_token = ? AND domain_token = ?
      ''',
      <Object?>[namespaceSelectors.namespaceToken, domainToken],
    );

    final records = <LifeMateLocalProjectionRecord>[];
    for (final row in rows) {
      final selectors = _StoredSelectors(
        environmentToken: row['environment_token'] as String,
        accountToken: row['account_token'] as String,
        namespaceToken: row['namespace_token'] as String,
        domainToken: row['domain_token'] as String,
        recordToken: row['record_token'] as String,
      );
      if (selectors.environmentToken != namespaceSelectors.environmentToken ||
          selectors.accountToken != namespaceSelectors.accountToken ||
          selectors.namespaceToken != namespaceSelectors.namespaceToken ||
          selectors.domainToken != domainToken) {
        throw const LifeMateLocalStoreCorruptionException();
      }
      records.add(
        await _decryptRow(
          row,
          expectedDomain: domain,
          selectors: selectors,
        ),
      );
    }
    records.sort((a, b) => a.storedAtUtc.compareTo(b.storedAtUtc));
    return records;
  }

  Future<void> deleteProjection({
    required LifeMateLocalNamespace namespace,
    required LifeMateLocalProjectionDomain domain,
    required String recordKey,
  }) async {
    _ensureOpen();
    final selectors = _selectors(namespace, domain, _requireRecordKey(recordKey));
    _database.execute(
      '''
      DELETE FROM lifemate_local_projection_records
      WHERE namespace_token = ? AND domain_token = ? AND record_token = ?
      ''',
      <Object?>[
        selectors.namespaceToken,
        selectors.domainToken,
        selectors.recordToken,
      ],
    );
  }

  /// Purges every local projection for one environment/account across all
  /// Persons. This is the primary sign-out/account-switch isolation primitive.
  Future<void> purgeAccount({
    required String environmentId,
    required String accountId,
  }) async {
    _ensureOpen();
    final normalizedEnvironment = _requireIdentifier(environmentId, 'environmentId');
    final normalizedAccount = _requireIdentifier(accountId, 'accountId');
    final environmentToken = _token('environment', <String>[normalizedEnvironment]);
    final accountToken = _token(
      'account',
      <String>[normalizedEnvironment, normalizedAccount],
    );
    _database.execute(
      '''
      DELETE FROM lifemate_local_projection_records
      WHERE environment_token = ? AND account_token = ?
      ''',
      <Object?>[environmentToken, accountToken],
    );
  }

  /// Purges all local projections for a backend/runtime environment, preventing
  /// test/staging/production projections from being mixed after a provider or
  /// environment switch.
  Future<void> purgeEnvironment(String environmentId) async {
    _ensureOpen();
    final normalizedEnvironment = _requireIdentifier(environmentId, 'environmentId');
    final environmentToken = _token('environment', <String>[normalizedEnvironment]);
    _database.execute(
      'DELETE FROM lifemate_local_projection_records WHERE environment_token = ?',
      <Object?>[environmentToken],
    );
  }

  Future<int> countNamespace(LifeMateLocalNamespace namespace) async {
    _ensureOpen();
    final selectors = _namespaceSelectors(namespace);
    final result = _database.select(
      '''
      SELECT COUNT(*) AS row_count
      FROM lifemate_local_projection_records
      WHERE namespace_token = ?
      ''',
      <Object?>[selectors.namespaceToken],
    );
    return result.first['row_count'] as int;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _database.dispose();
    _secretKey.destroy();
    _keyBytes.fillRange(0, _keyBytes.length, 0);
  }

  Future<LifeMateLocalProjectionRecord> _decryptRow(
    Row row, {
    required LifeMateLocalProjectionDomain expectedDomain,
    required _StoredSelectors selectors,
  }) async {
    try {
      final secretBox = SecretBox(
        _blob(row['ciphertext']),
        nonce: _blob(row['nonce']),
        mac: Mac(_blob(row['mac'])),
      );
      final cleartext = await _cipher.decrypt(
        secretBox,
        secretKey: _secretKey,
        aad: _aad(selectors),
      );
      final decoded = jsonDecode(utf8.decode(cleartext));
      if (decoded is! Map) {
        throw const LifeMateLocalStoreCorruptionException();
      }
      final envelope = Map<String, dynamic>.from(decoded);
      if (envelope['version'] != 1 ||
          envelope['namespaceToken'] != selectors.namespaceToken ||
          envelope['domainToken'] != selectors.domainToken ||
          envelope['recordToken'] != selectors.recordToken ||
          envelope['domain'] != expectedDomain.wireName) {
        throw const LifeMateLocalStoreCorruptionException();
      }

      final rawPayload = envelope['payload'];
      if (rawPayload is! Map) {
        throw const LifeMateLocalStoreCorruptionException();
      }
      final recordKey = envelope['recordKey']?.toString() ?? '';
      final storedAt = DateTime.tryParse(envelope['storedAtUtc']?.toString() ?? '');
      if (recordKey.isEmpty || storedAt == null) {
        throw const LifeMateLocalStoreCorruptionException();
      }
      final sourceUpdated = envelope['sourceUpdatedAtUtc'] == null
          ? null
          : DateTime.tryParse(envelope['sourceUpdatedAtUtc'].toString());
      if (envelope['sourceUpdatedAtUtc'] != null && sourceUpdated == null) {
        throw const LifeMateLocalStoreCorruptionException();
      }

      // Recompute the record selector from decrypted metadata so an unexpected
      // hash collision or row substitution cannot return a different record.
      final recomputedRecordToken = _token('record', <String>[
        selectors.namespaceToken,
        expectedDomain.wireName,
        recordKey,
      ]);
      if (recomputedRecordToken != selectors.recordToken) {
        throw const LifeMateLocalStoreCorruptionException();
      }

      return LifeMateLocalProjectionRecord(
        domain: expectedDomain,
        recordKey: recordKey,
        payload: Map<String, dynamic>.from(rawPayload),
        sourceRevision: _nullableTrim(envelope['sourceRevision']?.toString()),
        sourceUpdatedAtUtc: sourceUpdated?.toUtc(),
        syncCursor: _nullableTrim(envelope['syncCursor']?.toString()),
        contentVersion: _nullableTrim(envelope['contentVersion']?.toString()),
        ruleVersion: _nullableTrim(envelope['ruleVersion']?.toString()),
        storedAtUtc: storedAt.toUtc(),
      );
    } on LifeMateLocalStoreCorruptionException {
      rethrow;
    } on SecretBoxAuthenticationError {
      throw const LifeMateLocalStoreCorruptionException();
    } on FormatException {
      throw const LifeMateLocalStoreCorruptionException();
    } on TypeError {
      throw const LifeMateLocalStoreCorruptionException();
    }
  }

  void _migrateAndVerify() {
    _database.execute('PRAGMA foreign_keys = ON');
    final versionRows = _database.select('PRAGMA user_version');
    final currentVersion = versionRows.first['user_version'] as int;
    if (currentVersion > schemaVersion) {
      throw LifeMateLocalStoreSchemaException(
        'Database schema $currentVersion is newer than supported schema $schemaVersion.',
      );
    }
    if (currentVersion < 1) {
      _database.execute('BEGIN IMMEDIATE');
      try {
        _database.execute('''
          CREATE TABLE IF NOT EXISTS lifemate_local_projection_records (
            environment_token TEXT NOT NULL,
            account_token TEXT NOT NULL,
            namespace_token TEXT NOT NULL,
            domain_token TEXT NOT NULL,
            record_token TEXT NOT NULL,
            ciphertext BLOB NOT NULL,
            nonce BLOB NOT NULL,
            mac BLOB NOT NULL,
            PRIMARY KEY(namespace_token, domain_token, record_token)
          )
        ''');
        _database.execute('''
          CREATE INDEX IF NOT EXISTS idx_lifemate_local_projection_account
          ON lifemate_local_projection_records(environment_token, account_token)
        ''');
        _database.execute('''
          CREATE INDEX IF NOT EXISTS idx_lifemate_local_projection_domain
          ON lifemate_local_projection_records(namespace_token, domain_token)
        ''');
        _database.execute('PRAGMA user_version = 1');
        _database.execute('COMMIT');
      } catch (_) {
        try {
          _database.execute('ROLLBACK');
        } catch (_) {
          // Preserve the original migration failure.
        }
        rethrow;
      }
    }

    final finalVersion =
        _database.select('PRAGMA user_version').first['user_version'] as int;
    if (finalVersion != schemaVersion) {
      throw LifeMateLocalStoreSchemaException(
        'Database schema migration did not reach version $schemaVersion.',
      );
    }
  }

  _StoredSelectors _selectors(
    LifeMateLocalNamespace namespace,
    LifeMateLocalProjectionDomain domain,
    String recordKey,
  ) {
    final base = _namespaceSelectors(namespace);
    final domainToken = _token('domain', <String>[domain.wireName]);
    final recordToken = _token('record', <String>[
      base.namespaceToken,
      domain.wireName,
      recordKey,
    ]);
    return _StoredSelectors(
      environmentToken: base.environmentToken,
      accountToken: base.accountToken,
      namespaceToken: base.namespaceToken,
      domainToken: domainToken,
      recordToken: recordToken,
    );
  }

  _NamespaceSelectors _namespaceSelectors(LifeMateLocalNamespace namespace) {
    final environmentToken =
        _token('environment', <String>[namespace.environmentId]);
    final accountToken = _token(
      'account',
      <String>[namespace.environmentId, namespace.accountId],
    );
    final namespaceToken = _token(
      'namespace',
      <String>[
        namespace.environmentId,
        namespace.accountId,
        namespace.personId,
      ],
    );
    return _NamespaceSelectors(
      environmentToken: environmentToken,
      accountToken: accountToken,
      namespaceToken: namespaceToken,
    );
  }

  String _token(String purpose, List<String> parts) {
    final hmac = Hmac(sha256, _keyBytes);
    final bytes = utf8.encode(
      <String>['lifemate-local-v1', purpose, ...parts].join('\u0000'),
    );
    return base64Url.encode(hmac.convert(bytes).bytes).replaceAll('=', '');
  }

  List<int> _aad(_StoredSelectors selectors) => utf8.encode(
        <String>[
          'lifemate-local-envelope-v1',
          selectors.environmentToken,
          selectors.accountToken,
          selectors.namespaceToken,
          selectors.domainToken,
          selectors.recordToken,
        ].join('\u0000'),
      );

  static Uint8List _blob(Object? value) {
    if (value is Uint8List) return value;
    if (value is List<int>) return Uint8List.fromList(value);
    throw const LifeMateLocalStoreCorruptionException();
  }

  static String _requireRecordKey(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized.length > 200) {
      throw ArgumentError.value(
        value,
        'recordKey',
        'recordKey must contain 1-200 characters.',
      );
    }
    return normalized;
  }

  static String _requireIdentifier(String value, String field) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(value, field, '$field must not be empty.');
    }
    return normalized;
  }

  static String? _nullableTrim(String? value) {
    if (value == null) return null;
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  void _ensureOpen() {
    if (_closed) throw StateError('LifeMate local health store is closed.');
  }
}

final class _NamespaceSelectors {
  const _NamespaceSelectors({
    required this.environmentToken,
    required this.accountToken,
    required this.namespaceToken,
  });

  final String environmentToken;
  final String accountToken;
  final String namespaceToken;
}

final class _StoredSelectors extends _NamespaceSelectors {
  const _StoredSelectors({
    required super.environmentToken,
    required super.accountToken,
    required super.namespaceToken,
    required this.domainToken,
    required this.recordToken,
  });

  final String domainToken;
  final String recordToken;
}
