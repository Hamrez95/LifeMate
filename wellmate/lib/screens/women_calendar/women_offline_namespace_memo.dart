import 'package:lifemate_core/lifemate_core.dart';

/// Process-local identity memo for reopening the protected Women Health store
/// after connectivity drops.
///
/// The memo never crosses authenticated legacy accounts or API environments.
/// It intentionally is not persisted: process-kill/restart offline identity
/// recovery remains a separate acceptance gap and must not be claimed here.
final class WomenOfflineNamespaceMemo {
  WomenOfflineNamespaceMemo._();

  static final Map<String, LifeMateLocalNamespace> _resolved =
      <String, LifeMateLocalNamespace>{};

  static LifeMateLocalNamespace? lookup({
    required String environmentId,
    required String legacyAccountId,
  }) {
    final environment = environmentId.trim();
    final legacy = legacyAccountId.trim();
    if (environment.isEmpty || legacy.isEmpty) return null;
    return _resolved[_key(environment, legacy)];
  }

  static void remember({
    required String legacyAccountId,
    required LifeMateLocalNamespace namespace,
  }) {
    final environment = namespace.environmentId.trim();
    final legacy = legacyAccountId.trim();
    final account = namespace.accountId.trim();
    final person = namespace.personId.trim();
    if (environment.isEmpty ||
        legacy.isEmpty ||
        account.isEmpty ||
        person.isEmpty) {
      throw ArgumentError(
        'Women offline namespace memo requires environment, authenticated account, canonical account and Person.',
      );
    }
    _resolved[_key(environment, legacy)] = namespace;
  }

  static void forget({
    required String environmentId,
    required String legacyAccountId,
  }) {
    final environment = environmentId.trim();
    final legacy = legacyAccountId.trim();
    if (environment.isEmpty || legacy.isEmpty) return;
    _resolved.remove(_key(environment, legacy));
  }

  static void clearForTest() => _resolved.clear();

  static String _key(String environmentId, String legacyAccountId) =>
      '$environmentId\u0000$legacyAccountId';
}
