import 'history_suggestions.dart';
import 'recurrence.dart';

const int lifeMateSmartReentryRulesVersion = 1;

enum SmartReentryKind { appointment, injection }

class SmartReentryHistoryItem {
  const SmartReentryHistoryItem({
    required this.id,
    required this.kind,
    required this.occurredOn,
    required this.identityKey,
    required this.source,
    this.hasActiveRecurrence = false,
  });

  final String id;
  final SmartReentryKind kind;
  final DateTime occurredOn;
  final String identityKey;
  final Map<String, dynamic> source;
  final bool hasActiveRecurrence;
}

class SmartReentrySuppression {
  const SmartReentrySuppression({
    required this.patternKey,
    this.dismissedUntil,
    this.permanentlyMuted = false,
  });

  final String patternKey;
  final DateTime? dismissedUntil;
  final bool permanentlyMuted;

  bool blocks(DateTime now) => permanentlyMuted ||
      (dismissedUntil != null && dismissedUntil!.isAfter(now));
}

class SmartReentrySuggestion {
  const SmartReentrySuggestion({
    required this.patternKey,
    required this.kind,
    required this.identityKey,
    required this.latestSource,
    required this.latestOccurredOn,
    required this.averageIntervalDays,
    required this.reasonDaysAgo,
  });

  final String patternKey;
  final SmartReentryKind kind;
  final String identityKey;
  final Map<String, dynamic> latestSource;
  final DateTime latestOccurredOn;
  final int averageIntervalDays;
  final int reasonDaysAgo;
}

List<SmartReentrySuggestion> detectSmartReentrySuggestions({
  required Iterable<SmartReentryHistoryItem> history,
  required DateTime now,
  Iterable<SmartReentrySuppression> suppressions = const [],
  Set<String> existingPatternKeys = const {},
  int limit = 2,
}) {
  if (limit <= 0) return const [];
  final suppressionByKey = <String, SmartReentrySuppression>{
    for (final value in suppressions) value.patternKey: value,
  };
  final groups = <String, List<SmartReentryHistoryItem>>{};
  for (final item in history) {
    final normalized = normalizeLifeMateHistoryText(item.identityKey);
    if (normalized.isEmpty) continue;
    final key = '${item.kind.name}:$normalized';
    groups.putIfAbsent(key, () => []).add(item);
  }

  final suggestions = <SmartReentrySuggestion>[];
  for (final entry in groups.entries) {
    if (existingPatternKeys.contains(entry.key)) continue;
    final values = entry.value
      ..sort((left, right) => left.occurredOn.compareTo(right.occurredOn));
    if (values.length < 3 || values.any((value) => value.hasActiveRecurrence)) {
      continue;
    }
    final suppression = suppressionByKey[entry.key];
    if (suppression != null && suppression.blocks(now)) continue;

    final intervals = <int>[];
    for (var index = 1; index < values.length; index += 1) {
      final days = values[index].occurredOn
          .difference(values[index - 1].occurredOn)
          .inDays
          .abs();
      if (days > 0) intervals.add(days);
    }
    if (intervals.length < 2) continue;
    final average = intervals.reduce((a, b) => a + b) / intervals.length;
    if (average < 14 || average > 730) continue;
    final tolerance = (average * 0.35).clamp(7, 75).toDouble();
    if (intervals.any((days) => (days - average).abs() > tolerance)) continue;

    final latest = values.last;
    final daysAgo = now.difference(latest.occurredOn).inDays;
    if (daysAgo < average - tolerance || daysAgo > average + tolerance * 2) {
      continue;
    }
    suggestions.add(SmartReentrySuggestion(
      patternKey: entry.key,
      kind: latest.kind,
      identityKey: latest.identityKey,
      latestSource: Map<String, dynamic>.unmodifiable(latest.source),
      latestOccurredOn: latest.occurredOn,
      averageIntervalDays: average.round(),
      reasonDaysAgo: daysAgo,
    ));
  }

  suggestions.sort((left, right) {
    final leftDistance = (left.reasonDaysAgo - left.averageIntervalDays).abs();
    final rightDistance = (right.reasonDaysAgo - right.averageIntervalDays).abs();
    if (leftDistance != rightDistance) return leftDistance.compareTo(rightDistance);
    return right.latestOccurredOn.compareTo(left.latestOccurredOn);
  });
  return List<SmartReentrySuggestion>.unmodifiable(suggestions.take(limit));
}

bool smartReentryRecurrenceIsActive(dynamic raw, {required DateTime now}) {
  final rule = RecurrenceRule.fromJson(raw);
  if (!rule.enabled) return false;
  final endDate = rule.endDate;
  if (endDate == null) return true;
  final today = DateTime(now.year, now.month, now.day);
  final end = DateTime(endDate.year, endDate.month, endDate.day);
  return !end.isBefore(today);
}
