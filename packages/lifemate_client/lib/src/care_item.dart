enum CareItemType { medication, visit, injection }

enum CareItemSort { nearest, newest, oldest, name, type }

enum CareItemStatusFilter { all, active, upcoming, completed }

class CareItem {
  const CareItem({
    required this.id,
    required this.type,
    required this.title,
    required this.status,
    required this.searchText,
    this.seriesId,
    this.subtitle = '',
    this.scheduledAt,
    this.raw = const <String, dynamic>{},
  });

  final String id;
  final String? seriesId;
  final CareItemType type;
  final String title;
  final String subtitle;
  final String status;
  final DateTime? scheduledAt;
  final String searchText;
  final Map<String, dynamic> raw;

  bool get isCompleted => const <String>{
    'completed',
    'cancelled',
    'taken',
    'skipped',
    'stopped',
    'inactive',
  }.contains(status.toLowerCase());

  bool isUpcoming(DateTime now) =>
      !isCompleted && scheduledAt != null && !scheduledAt!.isBefore(now);

  bool get isActive => !isCompleted;

  static CareItem fromTreatmentPlan(Map<String, dynamic> plan) {
    final medication = _object(plan['medication']);
    final schedules = _objects(plan['schedules']);
    final name = _text(medication['name']) ?? 'دارو';
    final dose = _text(plan['doseText']) ?? '';
    final instructions = _text(plan['instructions']) ?? '';
    final firstTime = schedules.isEmpty
        ? null
        : _text(schedules.first['localTime']);
    final startDate = DateTime.tryParse(_text(plan['startDate']) ?? '');
    final scheduledAt = _combine(startDate, firstTime);
    return CareItem(
      id: _text(plan['id']) ?? '',
      seriesId: _text(plan['id']),
      type: CareItemType.medication,
      title: name,
      subtitle: [
        dose,
        if (firstTime != null) firstTime,
      ].where((value) => value.trim().isNotEmpty).join(' • '),
      status: (_text(plan['status']) ?? 'active').toLowerCase(),
      scheduledAt: scheduledAt,
      searchText: _search([
        name,
        dose,
        instructions,
        medication['strengthText'],
        medication['form'],
        medication['notes'],
      ]),
      raw: plan,
    );
  }

  static CareItem fromCareEvent(Map<String, dynamic> event) {
    final rawType = (_text(event['eventType']) ?? '').toLowerCase();
    final type = rawType == 'injection'
        ? CareItemType.injection
        : CareItemType.visit;
    final title =
        _text(event['title']) ??
        (type == CareItemType.injection ? 'تزریق' : 'ویزیت');
    final date = DateTime.tryParse(_text(event['scheduledLocalDate']) ?? '');
    final time = _text(event['scheduledLocalTime']);
    final scheduledAt =
        DateTime.tryParse(_text(event['scheduledAtUtc']) ?? '')?.toLocal() ??
        _combine(date, time);
    final provider = _text(event['providerName']) ?? '';
    final center = _text(event['centerName']) ?? '';
    final dose = _text(event['doseText']) ?? '';
    return CareItem(
      id: _text(event['id']) ?? '',
      seriesId: _text(event['seriesId']) ?? _text(event['id']),
      type: type,
      title: title,
      subtitle: [
        provider,
        dose,
        center,
        time ?? '',
      ].where((value) => value.trim().isNotEmpty).join(' • '),
      status: (_text(event['status']) ?? 'scheduled').toLowerCase(),
      scheduledAt: scheduledAt,
      searchText: _search([
        title,
        event['providerName'],
        event['specialty'],
        event['medicationName'],
        event['doseText'],
        event['administrationRoute'],
        event['reason'],
        event['instructions'],
        event['centerName'],
        event['addressLine'],
        event['phoneNumber'],
      ]),
      raw: event,
    );
  }

  static List<CareItem> filterAndSort(
    Iterable<CareItem> source, {
    CareItemType? type,
    CareItemStatusFilter status = CareItemStatusFilter.all,
    String query = '',
    CareItemSort sort = CareItemSort.nearest,
    DateTime? now,
  }) {
    final reference = now ?? DateTime.now();
    final normalizedQuery = _normalize(query);
    final items = source
        .where((item) {
          if (type != null && item.type != type) return false;
          final statusMatches = switch (status) {
            CareItemStatusFilter.all => true,
            CareItemStatusFilter.active => item.isActive,
            CareItemStatusFilter.upcoming => item.isUpcoming(reference),
            CareItemStatusFilter.completed => item.isCompleted,
          };
          if (!statusMatches) return false;
          return normalizedQuery.isEmpty ||
              item.searchText.contains(normalizedQuery);
        })
        .toList(growable: false);

    int compareDate(CareItem left, CareItem right, {required bool newest}) {
      final l = left.scheduledAt;
      final r = right.scheduledAt;
      if (l == null && r == null) return left.title.compareTo(right.title);
      if (l == null) return 1;
      if (r == null) return -1;
      return newest ? r.compareTo(l) : l.compareTo(r);
    }

    final mutable = items.toList();
    mutable.sort(
      (left, right) => switch (sort) {
        CareItemSort.nearest => compareDate(left, right, newest: false),
        CareItemSort.newest => compareDate(left, right, newest: true),
        CareItemSort.oldest => compareDate(left, right, newest: false),
        CareItemSort.name => left.title.compareTo(right.title),
        CareItemSort.type => left.type.index.compareTo(right.type.index),
      },
    );
    return mutable;
  }

  static String _search(Iterable<Object?> values) =>
      _normalize(values.map((value) => value?.toString() ?? '').join(' '));

  static String _normalize(String input) => input
      .trim()
      .toLowerCase()
      .replaceAll('ي', 'ی')
      .replaceAll('ك', 'ک')
      .replaceAll(RegExp(r'\s+'), ' ');

  static Map<String, dynamic> _object(dynamic value) =>
      value is Map<String, dynamic> ? value : const <String, dynamic>{};

  static List<Map<String, dynamic>> _objects(dynamic value) => value is List
      ? value.whereType<Map<String, dynamic>>().toList(growable: false)
      : const <Map<String, dynamic>>[];

  static String? _text(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static DateTime? _combine(DateTime? date, String? time) {
    if (date == null || time == null) return date;
    final parts = time.split(':');
    if (parts.length < 2) return date;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return date;
    return DateTime(date.year, date.month, date.day, hour, minute);
  }
}
