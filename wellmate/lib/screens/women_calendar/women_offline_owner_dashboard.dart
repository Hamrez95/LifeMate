import 'package:lifemate_client/lifemate_client.dart';

/// Owner-only last-known Women Health dashboard state.
///
/// Deliberately excludes currentUser/currentProfile, relationships, Circle
/// grants and any companion-sharing decision. Those remain server-authoritative
/// and are never reconstructed from an offline owner cache.
final class WomenOfflineOwnerDashboard {
  WomenOfflineOwnerDashboard({
    required WomenCalendarOfflineSnapshot snapshot,
    required Iterable<Map<String, dynamic>> dailyLogs,
  }) : profile = Map<String, dynamic>.unmodifiable(snapshot.profile),
       episodes = List<Map<String, dynamic>>.unmodifiable(
         snapshot.episodes.map(Map<String, dynamic>.unmodifiable),
       ),
       dailyLogs = List<Map<String, dynamic>>.unmodifiable(
         dailyLogs.map(
           (value) => Map<String, dynamic>.unmodifiable(
             Map<String, dynamic>.from(value),
           ),
         ),
       ),
       lifecycleState = snapshot.lifecycleState,
       storedAtUtc = snapshot.storedAtUtc.toUtc();

  final Map<String, dynamic> profile;
  final List<Map<String, dynamic>> episodes;
  final List<Map<String, dynamic>> dailyLogs;
  final WomenHealthLifecycleState lifecycleState;
  final DateTime storedAtUtc;

  Map<String, dynamic> toDashboardMap() => <String, dynamic>{
    'profile': profile,
    'episodes': episodes,
    'dailyLogs': dailyLogs,
    'offlineCached': true,
    'offlineCachedAtUtc': storedAtUtc.toIso8601String(),
  };
}
