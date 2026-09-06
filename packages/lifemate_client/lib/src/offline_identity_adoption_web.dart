import 'package:lifemate_core/lifemate_core.dart';

final class LifeMateOfflineIdentityAdoption {
  LifeMateOfflineIdentityAdoption({
    required String environmentId,
    required String legacyAccountId,
    required String accountId,
    required String personId,
    required DateTime adoptedAtUtc,
  }) : environmentId = environmentId.trim(),
       legacyAccountId = legacyAccountId.trim(),
       accountId = accountId.trim(),
       personId = personId.trim(),
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
}

abstract interface class LifeMateOfflineIdentityStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

final class LifeMateOfflineIdentityAdoptionStore {
  const LifeMateOfflineIdentityAdoptionStore._();

  factory LifeMateOfflineIdentityAdoptionStore.secure({Object? storage}) =>
      throw _unsupported();

  factory LifeMateOfflineIdentityAdoptionStore.forTesting(
    LifeMateOfflineIdentityStorage storage,
  ) => throw _unsupported();

  Future<void> remember({
    required String environmentId,
    required String legacyAccountId,
    required String accountId,
    required String personId,
    DateTime? adoptedAtUtc,
  }) => Future<void>.error(_unsupported());

  Future<LifeMateOfflineIdentityAdoption?> lookup({
    required String environmentId,
    required String legacyAccountId,
  }) => Future<LifeMateOfflineIdentityAdoption?>.error(_unsupported());

  Future<void> forget({
    required String environmentId,
    required String legacyAccountId,
  }) => Future<void>.error(_unsupported());

  Future<void> clear() => Future<void>.error(_unsupported());

  static UnsupportedError _unsupported() => UnsupportedError(
    'Protected offline identity adoption is unavailable on web.',
  );
}

final class LifeMateOfflineIdentityAdoptionCorruptionException
    implements Exception {
  const LifeMateOfflineIdentityAdoptionCorruptionException();

  @override
  String toString() =>
      'LifeMate offline identity adoption metadata is unavailable or malformed.';
}
