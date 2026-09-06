import 'package:lifemate_client/lifemate_client.dart';

/// Fail-closed policy for the richer owner check-in offline fallback.
///
/// Circle/sharing state is server-authoritative. A local replay may only carry
/// owner-private health fields when doing so cannot enable or revoke sharing.
final class WomenCompanionDailyLogOfflinePolicy {
  const WomenCompanionDailyLogOfflinePolicy._();

  static const Set<int> _transientStatusCodes = <int>{
    0,
    408,
    429,
    500,
    502,
    503,
    504,
  };

  static bool canQueueAfter(LifeMateApiException error) =>
      _transientStatusCodes.contains(error.statusCode);

  static bool canQueuePrivateMutation({
    required Map<String, dynamic>? current,
    required bool requestedShareWithCompanion,
  }) {
    if (requestedShareWithCompanion) return false;
    return current?['shareSummaryWithCompanion'] != true;
  }
}
