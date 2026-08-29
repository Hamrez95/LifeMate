import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'smart_reentry.dart';

class SmartReentrySuppressionStore {
  SmartReentrySuppressionStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  Future<List<SmartReentrySuppression>> read({required String accountId}) async {
    final raw = await _storage.read(key: _key(accountId));
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded.whereType<Map>().map((value) {
        final record = Map<String, dynamic>.from(value);
        return SmartReentrySuppression(
          patternKey: record['patternKey']?.toString() ?? '',
          dismissedUntil: DateTime.tryParse(
            record['dismissedUntil']?.toString() ?? '',
          ),
          permanentlyMuted: record['permanentlyMuted'] == true,
        );
      }).where((value) => value.patternKey.isNotEmpty).toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> dismiss({
    required String accountId,
    required String patternKey,
    required DateTime now,
    Duration cooldown = const Duration(days: 30),
  }) => _writeEntry(
        accountId: accountId,
        entry: SmartReentrySuppression(
          patternKey: patternKey,
          dismissedUntil: now.add(cooldown),
        ),
      );

  Future<void> mute({
    required String accountId,
    required String patternKey,
  }) => _writeEntry(
        accountId: accountId,
        entry: SmartReentrySuppression(
          patternKey: patternKey,
          permanentlyMuted: true,
        ),
      );

  Future<void> _writeEntry({
    required String accountId,
    required SmartReentrySuppression entry,
  }) async {
    final current = await read(accountId: accountId);
    final next = <SmartReentrySuppression>[
      ...current.where((value) => value.patternKey != entry.patternKey),
      entry,
    ];
    await _storage.write(
      key: _key(accountId),
      value: jsonEncode(next.map((value) => {
        'patternKey': value.patternKey,
        'dismissedUntil': value.dismissedUntil?.toIso8601String(),
        'permanentlyMuted': value.permanentlyMuted,
      }).toList(growable: false)),
    );
  }

  static String _key(String accountId) =>
      'lifemate.smart_reentry.v$lifeMateSmartReentryRulesVersion.$accountId';
}
