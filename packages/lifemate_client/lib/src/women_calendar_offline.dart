import 'women_calendar.dart';

/// Canonical deterministic Women Health calendar version already emitted by
/// lifemate-api. Offline prediction must fail closed when a cached snapshot was
/// produced by a different algorithm instead of silently rewriting history.
final class WomenCalendarOfflineEngine {
  const WomenCalendarOfflineEngine._();

  static const String canonicalAlgorithmVersion = 'calendar-estimate-v1';

  static WomenCalendarEstimate calculateFromCanonicalSnapshot({
    required Map<String, dynamic> profile,
    required Iterable<Map<String, dynamic>> episodes,
    DateTime? today,
  }) {
    final algorithmVersion = _requiredText(
      profile['algorithmVersion'],
      'algorithmVersion',
    );
    if (algorithmVersion != canonicalAlgorithmVersion) {
      throw WomenCalendarAlgorithmVersionMismatchException(
        cachedVersion: algorithmVersion,
        supportedVersion: canonicalAlgorithmVersion,
      );
    }

    final lastPeriodStart = _requiredDate(
      profile['lastPeriodStart'],
      'lastPeriodStart',
    );
    final cycleLength = _requiredInt(profile['cycleLength'], 'cycleLength');
    final periodLength = _requiredInt(profile['periodLength'], 'periodLength');
    final periodStarts = <DateTime>[];
    for (final episode in episodes) {
      periodStarts.add(_requiredDate(episode['startedOn'], 'startedOn'));
    }

    return WomenCalendarEstimate.calculateFromEpisodes(
      lastPeriodStart: lastPeriodStart,
      configuredCycleLength: cycleLength,
      periodLength: periodLength,
      periodStarts: periodStarts,
      today: today,
    );
  }

  /// Personal cycle reminders are owner-local execution. They remain enabled
  /// only while Women Health itself is active. Pregnancy/postpartum/resumable
  /// lifecycle states suppress period reminders until the canonical lifecycle
  /// explicitly returns to active.
  static bool shouldSchedulePersonalCycleReminders({
    required bool womenHealthEnabled,
    required bool remindersEnabled,
    required WomenHealthLifecycleState lifecycleState,
  }) {
    return womenHealthEnabled &&
        remindersEnabled &&
        lifecycleState == WomenHealthLifecycleState.active;
  }

  static String _requiredText(Object? value, String field) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) throw FormatException('Missing $field.');
    return text;
  }

  static int _requiredInt(Object? value, String field) {
    if (value is int) return value;
    final parsed = int.tryParse(value?.toString() ?? '');
    if (parsed == null) throw FormatException('Invalid $field.');
    return parsed;
  }

  static DateTime _requiredDate(Object? value, String field) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed == null) throw FormatException('Invalid $field.');
    return DateTime(parsed.year, parsed.month, parsed.day);
  }
}

enum WomenHealthLifecycleState {
  active('active'),
  pausedForPregnancy('paused_for_pregnancy'),
  postpartumRecovery('postpartum_recovery'),
  resumable('resumable');

  const WomenHealthLifecycleState(this.wireName);

  final String wireName;

  static WomenHealthLifecycleState parse(Object? value) {
    final wireName = value?.toString().trim() ?? '';
    for (final state in values) {
      if (state.wireName == wireName) return state;
    }
    throw FormatException('Unsupported Women Health lifecycle state.');
  }
}

final class WomenCalendarAlgorithmVersionMismatchException
    implements Exception {
  const WomenCalendarAlgorithmVersionMismatchException({
    required this.cachedVersion,
    required this.supportedVersion,
  });

  final String cachedVersion;
  final String supportedVersion;

  @override
  String toString() =>
      'Women calendar algorithm version mismatch: cached=$cachedVersion, supported=$supportedVersion.';
}
