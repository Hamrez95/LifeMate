import 'capabilities.dart';
import 'cocoon_pregnancy.dart';
import 'cocoon_pregnancy_daily_api.dart' show CocoonApprovedSymptomCatalog;
import 'lifemate_api_client.dart' show AccessTokenProvider;
import 'offline_sync_result.dart';

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

  Future<void> enqueueDailyCheckIn({
    required String clientRequestId,
    required DateTime observedAtUtc,
    required DateTime localDate,
    required String feeling,
    required String energy,
    DateTime? createdAtUtc,
  }) => Future<void>.error(_unsupported());

  Future<void> enqueueSymptom({
    required String clientRequestId,
    required DateTime observedAtUtc,
    required DateTime localDate,
    required String symptomCode,
    required String intensity,
    required CocoonApprovedSymptomCatalog approvedCatalog,
    String? note,
    DateTime? createdAtUtc,
  }) => Future<void>.error(_unsupported());

  Future<void> enqueueMood({
    required String clientRequestId,
    required DateTime observedAtUtc,
    required DateTime localDate,
    required String moodCode,
    DateTime? createdAtUtc,
  }) => Future<void>.error(_unsupported());

  Future<void> enqueueMeasurement({
    required String clientRequestId,
    required String observationType,
    required double valuePrimary,
    double? valueSecondary,
    String? note,
    required DateTime observedAtUtc,
    required DateTime observedLocalDate,
    DateTime? createdAtUtc,
  }) => Future<void>.error(_unsupported());

  Future<Set<String>> pendingPregnancyMutationIds() =>
      Future<Set<String>>.error(_unsupported());

  Future<LifeMateOfflineSyncResult> flushPending() =>
      Future<LifeMateOfflineSyncResult>.error(_unsupported());

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
