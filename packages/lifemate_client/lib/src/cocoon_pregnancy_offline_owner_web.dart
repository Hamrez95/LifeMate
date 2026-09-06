import 'capabilities.dart';
import 'cocoon_pregnancy.dart';
import 'lifemate_api_client.dart' show AccessTokenProvider;

typedef CocoonCanonicalIdentityResolver =
    Future<LifeMateCapabilitySnapshot> Function();

final class CocoonPregnancyOfflineOwnerCoordinator {
  CocoonPregnancyOfflineOwnerCoordinator({
    required Uri apiBaseUri,
    required String legacyAccountId,
    required AccessTokenProvider accessToken,
    required CocoonCanonicalIdentityResolver identityResolver,
    Object? identityStore,
    Object? localStore,
    Object? legacyStorage,
    String timeZone = 'Asia/Tehran',
  });

  Future<void> cacheAuthoritativeBootstrap(
    CocoonBootstrapSnapshot bootstrap,
  ) => Future<void>.error(_unsupported());

  Future<CocoonPregnancySnapshot?> readCachedOwnerSnapshot() =>
      Future<CocoonPregnancySnapshot?>.error(_unsupported());

  Future<void> forgetAdoptedOwner() => Future<void>.error(_unsupported());

  static UnsupportedError _unsupported() => UnsupportedError(
    'Protected Cocoon offline owner cache is unavailable on web.',
  );
}

final class CocoonOfflineOwnerIdentityMismatchException implements Exception {
  const CocoonOfflineOwnerIdentityMismatchException();

  @override
  String toString() =>
      'Cocoon bootstrap Person does not match the canonical authenticated Person.';
}
