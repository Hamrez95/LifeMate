import 'package:lifemate_client/lifemate_client.dart';

import 'women_episode_offline_bridge.dart';

/// Reconnect path for the advanced Women Calendar owner screen.
///
/// Durable owner mutations are offered to the canonical server before the
/// authoritative dashboard read. Any mutation retained for retry/conflict is
/// then projected explicitly over that fresh server snapshot.
final class WomenEpisodeDashboardLoader {
  const WomenEpisodeDashboardLoader(this.apiClient);

  final LifeMateApiClient apiClient;

  Future<Map<String, dynamic>> load({
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    WomenEpisodeOfflineBridge? offline;
    try {
      try {
        offline = await WomenEpisodeOfflineBridge.open(apiClient: apiClient);
        await offline.flush();
      } on UnsupportedError {
        // Web deliberately has no protected PHI persistence.
      } on LifeMateApiException {
        // The canonical dashboard request below owns user-visible API errors.
      } on StateError {
        // Protected local runtime unavailable; remain online-authoritative.
      }

      final dashboard = await apiClient.getWomenCalendarDashboard(
        fromDate: fromDate,
        toDate: toDate,
      );
      if (offline == null) return dashboard;
      final serverEpisodes =
          (dashboard['episodes'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<Map<String, dynamic>>()
              .toList(growable: false);
      final projected = await offline.project(serverEpisodes);
      return <String, dynamic>{...dashboard, 'episodes': projected};
    } finally {
      offline?.close();
    }
  }
}
