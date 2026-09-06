import 'package:lifemate_client/lifemate_client.dart';

/// Period episode fallback is owner-private only. Authorization, sharing and
/// validation failures stay server-authoritative and must never become queued
/// local health mutations.
final class WomenEpisodeOfflinePolicy {
  const WomenEpisodeOfflinePolicy._();

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
}
