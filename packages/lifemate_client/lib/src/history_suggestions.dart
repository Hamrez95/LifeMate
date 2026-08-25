enum LifeMateHistorySuggestionKind {
  doctor,
  center,
  medication,
  injection,
  careAction,
}

class LifeMateHistoryUsage {
  const LifeMateHistoryUsage({
    required this.kind,
    required this.value,
    required this.usedAt,
    this.context,
  });

  final LifeMateHistorySuggestionKind kind;
  final String value;
  final DateTime usedAt;
  final String? context;
}

class LifeMateHistorySuggestion {
  const LifeMateHistorySuggestion({
    required this.kind,
    required this.value,
    required this.usageCount,
    required this.lastUsedAt,
    this.context,
  });

  final LifeMateHistorySuggestionKind kind;
  final String value;
  final int usageCount;
  final DateTime lastUsedAt;
  final String? context;
}

String normalizeLifeMateHistoryText(String input) {
  const persianDigits = '\u06f0\u06f1\u06f2\u06f3\u06f4\u06f5\u06f6\u06f7\u06f8\u06f9';
  const arabicDigits = '\u0660\u0661\u0662\u0663\u0664\u0665\u0666\u0667\u0668\u0669';
  var value = input
      .trim()
      .toLowerCase()
      .replaceAll('\u064a', '\u06cc')
      .replaceAll('\u0649', '\u06cc')
      .replaceAll('\u0643', '\u06a9')
      .replaceAll('\u200c', ' ')
      .replaceAll('\u200f', '')
      .replaceAll('\u200e', '');
  for (var index = 0; index < 10; index += 1) {
    value = value
        .replaceAll(persianDigits[index], '$index')
        .replaceAll(arabicDigits[index], '$index');
  }
  return value.replaceAll(RegExp(r'\s+'), ' ').trim();
}

List<LifeMateHistorySuggestion> rankLifeMateHistorySuggestions({
  required Iterable<LifeMateHistoryUsage> history,
  required String query,
  required LifeMateHistorySuggestionKind kind,
  int limit = 6,
}) {
  final normalizedQuery = normalizeLifeMateHistoryText(query);
  if (normalizedQuery.length < 2 || limit <= 0) {
    return const <LifeMateHistorySuggestion>[];
  }

  final groups = <String, List<LifeMateHistoryUsage>>{};
  for (final item in history) {
    if (item.kind != kind) continue;
    final normalizedValue = normalizeLifeMateHistoryText(item.value);
    if (normalizedValue.isEmpty || !normalizedValue.contains(normalizedQuery)) {
      continue;
    }
    groups.putIfAbsent(normalizedValue, () => <LifeMateHistoryUsage>[]).add(item);
  }

  final ranked = groups.entries.map((entry) {
    final values = entry.value
      ..sort((left, right) => right.usedAt.compareTo(left.usedAt));
    final latest = values.first;
    return (
      normalized: entry.key,
      prefix: entry.key.startsWith(normalizedQuery),
      suggestion: LifeMateHistorySuggestion(
        kind: kind,
        value: latest.value.trim(),
        usageCount: values.length,
        lastUsedAt: latest.usedAt,
        context: latest.context?.trim().isEmpty == true
            ? null
            : latest.context?.trim(),
      ),
    );
  }).toList(growable: false);

  ranked.sort((left, right) {
    if (left.prefix != right.prefix) return left.prefix ? -1 : 1;
    final recent = right.suggestion.lastUsedAt.compareTo(
      left.suggestion.lastUsedAt,
    );
    if (recent != 0) return recent;
    final frequent = right.suggestion.usageCount.compareTo(
      left.suggestion.usageCount,
    );
    if (frequent != 0) return frequent;
    return left.normalized.compareTo(right.normalized);
  });

  return List<LifeMateHistorySuggestion>.unmodifiable(
    ranked.take(limit).map((item) => item.suggestion),
  );
}
