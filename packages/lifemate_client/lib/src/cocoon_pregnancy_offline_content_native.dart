import 'package:lifemate_core/lifemate_core.dart';

import 'shared_offline_runtime_native.dart' show LifeMateSharedOfflineRuntime;

final class CocoonPregnancyOfflineContentRecord {
  const CocoonPregnancyOfflineContentRecord({
    required this.recordKey,
    required this.payload,
    required this.contentVersion,
    required this.ruleVersion,
    required this.storedAtUtc,
  });

  final String recordKey;
  final Map<String, dynamic> payload;
  final String contentVersion;
  final String? ruleVersion;
  final DateTime storedAtUtc;
}

/// Protected owner-scoped cache for approved Cocoon clinical/educational
/// content. The cache stores versioned content payloads only; it does not make
/// enrollment, entitlement, sharing or safety decisions authoritative.
final class CocoonPregnancyOfflineContentCache {
  CocoonPregnancyOfflineContentCache._({
    required LifeMateLocalHealthStore store,
    required LifeMateLocalNamespace namespace,
    required bool ownsStore,
  }) : _store = store,
       _namespace = namespace,
       _ownsStore = ownsStore;

  static const _payloadVersion = 1;
  static const _recordPrefix = 'approved-content:';

  final LifeMateLocalHealthStore _store;
  final LifeMateLocalNamespace _namespace;
  final bool _ownsStore;
  bool _closed = false;

  static Future<CocoonPregnancyOfflineContentCache> open({
    required LifeMateSharedOfflineRuntime runtime,
    LifeMateLocalHealthStore? store,
    DateTime Function()? now,
  }) async {
    final ownsStore = store == null;
    final localStore = store ?? await LifeMateLocalHealthStore.openDefault(now: now);
    return CocoonPregnancyOfflineContentCache._(
      store: localStore,
      namespace: runtime.namespace.toLocalNamespace(),
      ownsStore: ownsStore,
    );
  }

  Future<void> writeApprovedContent({
    required String recordKey,
    required Map<String, dynamic> payload,
    required String contentVersion,
    String? ruleVersion,
  }) async {
    _requireOpen();
    final key = _requiredToken(recordKey, 'recordKey');
    final version = _requiredToken(contentVersion, 'contentVersion');
    final normalizedRuleVersion = ruleVersion == null
        ? null
        : _requiredToken(ruleVersion, 'ruleVersion');

    await _store.putProjection(
      namespace: _namespace,
      domain: LifeMateLocalProjectionDomain.pregnancyContent,
      recordKey: '$_recordPrefix$key',
      payload: <String, dynamic>{
        'payloadVersion': _payloadVersion,
        'content': Map<String, dynamic>.from(payload),
      },
      contentVersion: version,
      ruleVersion: normalizedRuleVersion,
    );
  }

  Future<CocoonPregnancyOfflineContentRecord?> readApprovedContent({
    required String recordKey,
  }) async {
    _requireOpen();
    final key = _requiredToken(recordKey, 'recordKey');
    final record = await _store.readProjection(
      namespace: _namespace,
      domain: LifeMateLocalProjectionDomain.pregnancyContent,
      recordKey: '$_recordPrefix$key',
    );
    if (record == null || record.payload['payloadVersion'] != _payloadVersion) {
      return null;
    }
    final content = record.payload['content'];
    final contentVersion = record.contentVersion?.trim();
    if (content is! Map<String, dynamic> ||
        contentVersion == null ||
        contentVersion.isEmpty) {
      return null;
    }
    return CocoonPregnancyOfflineContentRecord(
      recordKey: key,
      payload: Map<String, dynamic>.unmodifiable(content),
      contentVersion: contentVersion,
      ruleVersion: record.ruleVersion,
      storedAtUtc: record.storedAtUtc,
    );
  }

  Future<void> deleteApprovedContent({required String recordKey}) async {
    _requireOpen();
    final key = _requiredToken(recordKey, 'recordKey');
    await _store.deleteProjection(
      namespace: _namespace,
      domain: LifeMateLocalProjectionDomain.pregnancyContent,
      recordKey: '$_recordPrefix$key',
    );
  }

  void close() {
    if (_closed) return;
    _closed = true;
    if (_ownsStore) _store.close();
  }

  void _requireOpen() {
    if (_closed) throw StateError('Cocoon offline content cache is closed.');
  }

  static String _requiredToken(String value, String field) {
    final normalized = value.trim();
    if (!RegExp(r'^[A-Za-z0-9._:-]{1,160}$').hasMatch(normalized)) {
      throw ArgumentError.value(value, field, '$field must be a stable token.');
    }
    return normalized;
  }
}
