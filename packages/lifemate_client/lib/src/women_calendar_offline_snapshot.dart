import 'package:lifemate_core/lifemate_core.dart';

import 'women_calendar_offline.dart';

/// Protected, Account + Person + environment-scoped owner snapshot used only
/// for offline Women Health continuity. Server state remains canonical and
/// Circle/partner state is deliberately excluded from this record.
final class WomenCalendarOfflineSnapshotStore {
  WomenCalendarOfflineSnapshotStore({
    required LifeMateLocalHealthStore store,
    required LifeMateLocalNamespace namespace,
  }) : _store = store,
       _namespace = namespace;

  static const _recordKey = 'women-calendar-owner-snapshot-v1';
  static const _version = 1;

  final LifeMateLocalHealthStore _store;
  final LifeMateLocalNamespace _namespace;

  Future<void> write({
    required Map<String, dynamic> profile,
    required Iterable<Map<String, dynamic>> episodes,
    required WomenHealthLifecycleState lifecycleState,
  }) async {
    final normalizedProfile = Map<String, dynamic>.from(profile);
    final normalizedEpisodes = episodes
        .map((value) => Map<String, dynamic>.from(value))
        .toList(growable: false);

    // Validate the exact cached inputs against the same deterministic policy
    // that will be used on read. A mismatched algorithm version or malformed
    // date therefore never becomes durable local truth.
    WomenCalendarOfflineEngine.calculateFromCanonicalSnapshot(
      profile: normalizedProfile,
      episodes: normalizedEpisodes,
    );

    await _store.putProjection(
      namespace: _namespace,
      domain: LifeMateLocalProjectionDomain.syncMetadata,
      recordKey: _recordKey,
      payload: <String, dynamic>{
        'version': _version,
        'profile': normalizedProfile,
        'episodes': normalizedEpisodes,
        'lifecycleState': lifecycleState.wireName,
      },
    );
  }

  Future<WomenCalendarOfflineSnapshot?> read() async {
    final record = await _store.readProjection(
      namespace: _namespace,
      domain: LifeMateLocalProjectionDomain.syncMetadata,
      recordKey: _recordKey,
    );
    if (record == null) return null;

    final payload = record.payload;
    if (payload['version'] != _version ||
        payload['profile'] is! Map ||
        payload['episodes'] is! List) {
      throw const FormatException('Invalid Women Health offline snapshot.');
    }

    final profile = <String, dynamic>{
      for (final entry in (payload['profile'] as Map).entries)
        entry.key.toString(): entry.value,
    };
    final episodes = <Map<String, dynamic>>[];
    for (final value in payload['episodes'] as List) {
      if (value is! Map) {
        throw const FormatException('Invalid Women Health offline episode.');
      }
      episodes.add(<String, dynamic>{
        for (final entry in value.entries) entry.key.toString(): entry.value,
      });
    }
    final lifecycleState = WomenHealthLifecycleState.parse(
      payload['lifecycleState'],
    );

    // Fail closed if an installed client cannot reproduce the server-approved
    // algorithm contract represented by this cache.
    WomenCalendarOfflineEngine.calculateFromCanonicalSnapshot(
      profile: profile,
      episodes: episodes,
    );

    return WomenCalendarOfflineSnapshot(
      profile: Map<String, dynamic>.unmodifiable(profile),
      episodes: List<Map<String, dynamic>>.unmodifiable(
        episodes.map(Map<String, dynamic>.unmodifiable),
      ),
      lifecycleState: lifecycleState,
      storedAtUtc: record.storedAtUtc,
    );
  }
}

final class WomenCalendarOfflineSnapshot {
  const WomenCalendarOfflineSnapshot({
    required this.profile,
    required this.episodes,
    required this.lifecycleState,
    required this.storedAtUtc,
  });

  final Map<String, dynamic> profile;
  final List<Map<String, dynamic>> episodes;
  final WomenHealthLifecycleState lifecycleState;
  final DateTime storedAtUtc;
}
