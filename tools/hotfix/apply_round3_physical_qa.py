from __future__ import annotations

from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, content: str) -> None:
    (ROOT / path).write_text(content, encoding="utf-8")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly 1 match, got {count}")
    return text.replace(old, new, 1)


def regex_once(text: str, pattern: str, replacement: str, label: str) -> str:
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly 1 regex match, got {count}")
    return updated


# ---------------------------------------------------------------------------
# 1) WomenCompanionApi must preserve the nested Supabase Edge Function prefix.
# ---------------------------------------------------------------------------
path = "packages/lifemate_client/lib/src/women_companion_api.dart"
text = read(path)
text = replace_once(
    text,
    """    final resolved = _baseUri.resolve(path);\n    final uri = query == null\n        ? resolved\n        : resolved.replace(queryParameters: query);""",
    """    final resolved = _resolve(path);\n    final uri = query == null\n        ? resolved\n        : resolved.replace(queryParameters: query);""",
    "women companion nested base resolution",
)
text = replace_once(
    text,
    """  static String _date(DateTime value) =>\n      '${value.year.toString().padLeft(4, '0')}-'\n      '${value.month.toString().padLeft(2, '0')}-'\n      '${value.day.toString().padLeft(2, '0')}';\n\n  static String? _emptyToNull(String? value) {""",
    """  Uri _resolve(String path) {\n    final base = _baseUri.toString().replaceFirst(RegExp(r'/+$'), '');\n    final relative = path.replaceFirst(RegExp(r'^/+'), '');\n    return Uri.parse('$base/$relative');\n  }\n\n  static String _date(DateTime value) =>\n      '${value.year.toString().padLeft(4, '0')}-'\n      '${value.month.toString().padLeft(2, '0')}-'\n      '${value.day.toString().padLeft(2, '0')}';\n\n  static String? _emptyToNull(String? value) {""",
    "women companion resolver helper",
)
write(path, text)

path = "packages/lifemate_client/test/women_companion_api_test.dart"
text = read(path)
insert = r'''

  test('daily log save preserves nested Supabase Edge Function base path', () async {
    late http.Request observed;
    final api = WomenCompanionApi(
      baseUri: Uri.parse(
        'https://project.supabase.co/functions/v1/lifemate-api',
      ),
      accessToken: () => 'access-token',
      httpClient: MockClient((request) async {
        observed = request;
        return http.Response(
          jsonEncode({
            'id': 'daily-1',
            'loggedOn': '2026-08-08',
            'mood': 'good',
            'energyLevel': 5,
            'painLevel': 3,
            'symptoms': ['headache'],
            'privateNotes': null,
            'shareSummaryWithCompanion': false,
            'version': 2,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await api.saveDailyLog(
      version: 1,
      loggedOn: DateTime(2026, 8, 8),
      mood: 'good',
      energyLevel: 5,
      painLevel: 3,
      symptoms: const ['headache'],
      shareSummaryWithCompanion: false,
    );

    expect(
      observed.url.path,
      '/functions/v1/lifemate-api/api/v1/women-calendar/daily-logs',
    );
  });
'''
text = replace_once(text, "\n}\n", insert + "\n}\n", "women companion path test")
write(path, text)


# ---------------------------------------------------------------------------
# 2) LifeMate floating notice: eliminate inherited debug yellow underlines.
# ---------------------------------------------------------------------------
path = "packages/lifemate_client/lib/src/app_notice.dart"
text = read(path)
text = replace_once(
    text,
    """                                              color: Color(0xFF253149),\n                                            ),""",
    """                                              color: Color(0xFF253149),\n                                              decoration: TextDecoration.none,\n                                            ),""",
    "notice title decoration",
)
text = replace_once(
    text,
    """                                            color: Color(0xFF4E596B),\n                                          ),""",
    """                                            color: Color(0xFF4E596B),\n                                            decoration: TextDecoration.none,\n                                          ),""",
    "notice message decoration",
)
write(path, text)

path = "packages/lifemate_client/test/app_notice_test.dart"
text = read(path)
insert = r'''

  testWidgets('LifeMate notice text never inherits debug underline decoration', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => LifeMateNotice.show(
                context,
                type: LifeMateNoticeType.error,
                title: 'ثبت انجام نشد',
                message: 'دوباره تلاش کن',
              ),
              child: const Text('show-error'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('show-error'));
    await tester.pump();

    final title = tester.widget<Text>(find.text('ثبت انجام نشد'));
    final message = tester.widget<Text>(find.text('دوباره تلاش کن'));
    expect(title.style?.decoration, TextDecoration.none);
    expect(message.style?.decoration, TextDecoration.none);
  });
'''
text = replace_once(text, "\n}\n", insert + "\n}\n", "notice decoration regression test")
write(path, text)


# ---------------------------------------------------------------------------
# 3) CareItem: dose-occurrence view + inclusive date-range filtering.
# ---------------------------------------------------------------------------
path = "packages/lifemate_client/lib/src/care_item.dart"
text = read(path)
needle = """  static CareItem fromCareEvent(Map<String, dynamic> event) {"""
factory = r'''  static CareItem fromDoseOccurrence(
    Map<String, dynamic> occurrence,
    Map<String, dynamic> plan,
  ) {
    final medication = _object(plan['medication']);
    final name = _text(medication['name']) ?? 'دارو';
    final dose = _text(plan['doseText']) ?? '';
    final instructions = _text(plan['instructions']) ?? '';
    final date = DateTime.tryParse(
      _text(occurrence['scheduledLocalDate']) ?? '',
    );
    final time = _text(occurrence['scheduledLocalTime']);
    final scheduledAt =
        DateTime.tryParse(_text(occurrence['scheduledAtUtc']) ?? '')?.toLocal() ??
        _combine(date, time);
    return CareItem(
      id: _text(occurrence['id']) ?? '',
      seriesId: _text(occurrence['treatmentPlanId']) ?? _text(plan['id']),
      type: CareItemType.medication,
      title: name,
      subtitle: dose,
      status: (_text(occurrence['status']) ?? 'scheduled').toLowerCase(),
      scheduledAt: scheduledAt,
      searchText: _search([
        name,
        dose,
        instructions,
        medication['strengthText'],
        medication['form'],
        medication['notes'],
      ]),
      // Medication details still expect the treatment-plan contract.
      raw: plan,
    );
  }

'''
text = replace_once(text, needle, factory + needle, "dose occurrence care item factory")
text = replace_once(
    text,
    """    CareItemSort sort = CareItemSort.nearest,\n    DateTime? now,\n  }) {""",
    """    CareItemSort sort = CareItemSort.nearest,\n    DateTime? now,\n    DateTime? fromDate,\n    DateTime? toDate,\n  }) {""",
    "care item date filter params",
)
text = replace_once(
    text,
    """          if (!statusMatches) return false;\n          return normalizedQuery.isEmpty ||\n              item.searchText.contains(normalizedQuery);""",
    """          if (!statusMatches) return false;\n          if (fromDate != null || toDate != null) {\n            final scheduled = item.scheduledAt;\n            if (scheduled == null) return false;\n            final day = DateTime(scheduled.year, scheduled.month, scheduled.day);\n            if (fromDate != null) {\n              final from = DateTime(fromDate.year, fromDate.month, fromDate.day);\n              if (day.isBefore(from)) return false;\n            }\n            if (toDate != null) {\n              final to = DateTime(toDate.year, toDate.month, toDate.day);\n              if (day.isAfter(to)) return false;\n            }\n          }\n          return normalizedQuery.isEmpty ||\n              item.searchText.contains(normalizedQuery);""",
    "care item inclusive date filtering",
)
write(path, text)

path = "packages/lifemate_client/test/care_item_test.dart"
text = read(path)
insert = r'''

  test('taken dose occurrence is a completed medication care item', () {
    final taken = CareItem.fromDoseOccurrence(
      {
        'id': 'dose-1',
        'treatmentPlanId': 'med-1',
        'scheduledLocalDate': '2026-08-08',
        'scheduledLocalTime': '09:30',
        'status': 'Taken',
      },
      {
        'id': 'med-1',
        'status': 'active',
        'doseText': '۱ عدد',
        'medication': {'name': 'ویتامین B'},
      },
    );

    expect(taken.type, CareItemType.medication);
    expect(taken.isCompleted, isTrue);
    expect(
      CareItem.filterAndSort(
        [taken],
        status: CareItemStatusFilter.completed,
      ),
      hasLength(1),
    );
  });

  test('date range filter is inclusive and uses occurrence date', () {
    final inside = CareItem.fromCareEvent({
      'id': 'visit-range',
      'eventType': 'appointment',
      'title': 'ویزیت بازه',
      'scheduledLocalDate': '2026-08-17',
      'scheduledLocalTime': '10:00',
      'status': 'scheduled',
    });
    final outside = CareItem.fromCareEvent({
      'id': 'visit-outside',
      'eventType': 'appointment',
      'title': 'ویزیت خارج بازه',
      'scheduledLocalDate': '2026-08-20',
      'scheduledLocalTime': '10:00',
      'status': 'scheduled',
    });

    final result = CareItem.filterAndSort(
      [inside, outside],
      fromDate: DateTime(2026, 8, 17),
      toDate: DateTime(2026, 8, 17),
    );
    expect(result.map((item) => item.id), ['visit-range']);
  });
'''
text = replace_once(text, "\n}\n", insert + "\n}\n", "care item round3 tests")
write(path, text)


# ---------------------------------------------------------------------------
# 4) Treatments hub: real dose completion state + date range filter.
# ---------------------------------------------------------------------------
path = "wellmate/lib/screens/treatments/treatments_screen.dart"
text = read(path)
new_state = r'''class _TreatmentsScreenState extends State<TreatmentsScreen> {
  final _search = TextEditingController();
  bool _loading = true;
  String? _error;
  List<CareItem> _planItems = const [];
  List<CareItem> _careEventItems = const [];
  List<CareItem> _doseItems = const [];
  CareItemType? _type;
  CareItemStatusFilter _status = CareItemStatusFilter.all;
  CareItemSort _sort = CareItemSort.nearest;
  DateTimeRange? _dateRange;

  @override
  void initState() {
    super.initState();
    _search.addListener(_onQueryChanged);
    _load();
  }

  @override
  void didUpdateWidget(covariant TreatmentsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _load();
  }

  @override
  void dispose() {
    _search
      ..removeListener(_onQueryChanged)
      ..dispose();
    super.dispose();
  }

  void _onQueryChanged() => setState(() {});

  Future<List<Map<String, dynamic>>> _loadBoundedRange(
    DateTime fromDate,
    DateTime toDate,
    Future<List<Map<String, dynamic>>> Function(DateTime, DateTime) loader,
  ) async {
    final from = DateTime(fromDate.year, fromDate.month, fromDate.day);
    final to = DateTime(toDate.year, toDate.month, toDate.day);
    final values = <Map<String, dynamic>>[];
    var cursor = from;
    while (!cursor.isAfter(to)) {
      final candidate = cursor.add(const Duration(days: 30));
      final chunkEnd = candidate.isAfter(to) ? to : candidate;
      values.addAll(await loader(cursor, chunkEnd));
      cursor = chunkEnd.add(const Duration(days: 1));
    }
    final unique = <String, Map<String, dynamic>>{};
    for (final value in values) {
      final key = value['id']?.toString() ?? value.toString();
      unique[key] = value;
    }
    return unique.values.toList(growable: false);
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final api = context.read<LifeMateApiClient>();
      final now = DateTime.now();
      final range = _dateRange;
      final fromDate = range?.start ?? now.subtract(const Duration(days: 31));
      final toDate = range?.end ?? now.add(const Duration(days: 31));
      var failedSources = 0;

      Future<List<Map<String, dynamic>>> safeLoad(
        Future<List<Map<String, dynamic>>> request,
        String label,
      ) async {
        try {
          return await request;
        } catch (error) {
          failedSources += 1;
          debugPrint('WellMate care hub $label load failed: $error');
          return const <Map<String, dynamic>>[];
        }
      }

      final results = await Future.wait<List<Map<String, dynamic>>>([
        safeLoad(api.getTreatmentPlans(), 'treatments'),
        safeLoad(
          _loadBoundedRange(
            fromDate,
            toDate,
            (from, to) => api.getCareEvents(fromDate: from, toDate: to),
          ),
          'care events',
        ),
        safeLoad(
          _loadBoundedRange(
            fromDate,
            toDate,
            (from, to) => api.getDoseOccurrences(fromDate: from, toDate: to),
          ),
          'dose occurrences',
        ),
      ]);

      if (failedSources == 3) {
        throw StateError('All treatment sources are unavailable.');
      }

      final plans = results[0];
      final careEvents = results[1];
      final doses = results[2];
      final plansById = <String, Map<String, dynamic>>{
        for (final plan in plans) plan['id'].toString(): plan,
      };
      final doseItems = <CareItem>[];
      for (final dose in doses) {
        final plan = plansById[dose['treatmentPlanId']?.toString() ?? ''];
        if (plan == null) continue;
        doseItems.add(CareItem.fromDoseOccurrence(dose, plan));
      }

      if (!mounted) return;
      setState(() {
        _planItems = List<CareItem>.unmodifiable(
          plans.map(CareItem.fromTreatmentPlan),
        );
        _careEventItems = List<CareItem>.unmodifiable(
          careEvents.map(CareItem.fromCareEvent),
        );
        _doseItems = List<CareItem>.unmodifiable(doseItems);
      });
    } catch (error) {
      debugPrint('WellMate care hub load failed: $error');
      if (mounted) {
        setState(() => _error = 'درمان‌ها و برنامه‌های مراقبتی دریافت نشدند.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<CareItem> _groupCareSeries() {
    final bySeries = <String, CareItem>{};
    for (final item in _careEventItems) {
      final key = item.seriesId ?? item.id;
      final previous = bySeries[key];
      if (previous == null ||
          (item.scheduledAt != null &&
              (previous.scheduledAt == null ||
                  item.scheduledAt!.isAfter(previous.scheduledAt!)))) {
        bySeries[key] = item;
      }
    }
    return bySeries.values.toList(growable: false);
  }

  List<CareItem> get _visible {
    final range = _dateRange;
    final source = <CareItem>[];
    if (range != null) {
      // A range is an occurrence/history view, so medication rows come from
      // real dose occurrences rather than the long-lived treatment plan.
      source
        ..addAll(_doseItems)
        ..addAll(_careEventItems);
    } else {
      source
        ..addAll(_planItems)
        ..addAll(_groupCareSeries());
      // The plan itself stays active after a dose is taken. Completed filtering
      // therefore also needs resolved dose occurrences as first-class rows.
      if (_status == CareItemStatusFilter.completed) {
        source.addAll(_doseItems.where((item) => item.isCompleted));
      }
    }

    return CareItem.filterAndSort(
      source,
      type: _type,
      status: _status,
      query: _search.text,
      sort: _sort,
      fromDate: range?.start,
      toDate: range?.end,
    );
  }

  Future<void> _pickDateRange() async {
    final today = DateTime.now();
    final current = _dateRange;
    final start = await showAppDatePicker(
      context: context,
      initialDate: current?.start ?? today.subtract(const Duration(days: 7)),
      firstDate: DateTime(2020),
      lastDate: today.add(const Duration(days: 730)),
      title: 'از تاریخ',
    );
    if (start == null || !mounted) return;
    final initialEnd = current?.end != null && !current!.end.isBefore(start)
        ? current.end
        : start;
    final end = await showAppDatePicker(
      context: context,
      initialDate: initialEnd,
      firstDate: start,
      lastDate: today.add(const Duration(days: 730)),
      title: 'تا تاریخ',
    );
    if (end == null || !mounted) return;
    setState(() {
      _dateRange = DateTimeRange(
        start: DateTime(start.year, start.month, start.day),
        end: DateTime(end.year, end.month, end.day),
      );
    });
    await _load();
  }

  Future<void> _clearDateRange() async {
    if (_dateRange == null) return;
    setState(() => _dateRange = null);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final range = _dateRange;
    return Material(
      color: Colors.transparent,
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          key: const ValueKey('wellmate-unified-care-hub'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 120),
          children: [
            const Text(
              'درمان‌های من',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            const Text(
              'دارو، ویزیت و تزریق در یک نمای قابل جست‌وجو و مرتب‌سازی.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('care-hub-search'),
              controller: _search,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                hintText: 'جست‌وجو در نام، پزشک، درمانگاه، آدرس یا توضیحات',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _TypeChip(
                    label: 'همه',
                    selected: _type == null,
                    onTap: () => setState(() => _type = null),
                  ),
                  _TypeChip(
                    label: 'دارو',
                    selected: _type == CareItemType.medication,
                    onTap: () =>
                        setState(() => _type = CareItemType.medication),
                  ),
                  _TypeChip(
                    label: 'ویزیت',
                    selected: _type == CareItemType.visit,
                    onTap: () => setState(() => _type = CareItemType.visit),
                  ),
                  _TypeChip(
                    label: 'تزریق',
                    selected: _type == CareItemType.injection,
                    onTap: () => setState(() => _type = CareItemType.injection),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<CareItemStatusFilter>(
                    key: const ValueKey('care-hub-status-filter'),
                    initialValue: _status,
                    decoration: const InputDecoration(labelText: 'وضعیت'),
                    items: const [
                      DropdownMenuItem(
                        value: CareItemStatusFilter.all,
                        child: Text('همه وضعیت‌ها'),
                      ),
                      DropdownMenuItem(
                        value: CareItemStatusFilter.active,
                        child: Text('فعال'),
                      ),
                      DropdownMenuItem(
                        value: CareItemStatusFilter.upcoming,
                        child: Text('آینده'),
                      ),
                      DropdownMenuItem(
                        value: CareItemStatusFilter.completed,
                        child: Text('تمام‌شده'),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _status = value ?? _status),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<CareItemSort>(
                    key: const ValueKey('care-hub-sort'),
                    initialValue: _sort,
                    decoration: const InputDecoration(labelText: 'مرتب‌سازی'),
                    items: const [
                      DropdownMenuItem(
                        value: CareItemSort.nearest,
                        child: Text('نزدیک‌ترین'),
                      ),
                      DropdownMenuItem(
                        value: CareItemSort.newest,
                        child: Text('جدیدترین'),
                      ),
                      DropdownMenuItem(
                        value: CareItemSort.oldest,
                        child: Text('قدیمی‌ترین'),
                      ),
                      DropdownMenuItem(
                        value: CareItemSort.name,
                        child: Text('نام'),
                      ),
                      DropdownMenuItem(
                        value: CareItemSort.type,
                        child: Text('نوع'),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _sort = value ?? _sort),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const ValueKey('care-hub-date-range-filter'),
                    onPressed: _loading ? null : _pickDateRange,
                    icon: const Icon(Icons.date_range_rounded),
                    label: Text(
                      range == null
                          ? 'بازه زمانی'
                          : '${formatAppDate(context, range.start)} تا ${formatAppDate(context, range.end)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                if (range != null) ...[
                  const SizedBox(width: 6),
                  IconButton(
                    key: const ValueKey('care-hub-clear-date-range'),
                    tooltip: 'حذف بازه زمانی',
                    onPressed: _loading ? null : _clearDateRange,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 18),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _MessageCard(
                icon: Icons.cloud_off_rounded,
                message: _error!,
                actionLabel: 'تلاش دوباره',
                onAction: _load,
              )
            else if (visible.isEmpty)
              _MessageCard(
                icon: _type == CareItemType.injection
                    ? Icons.vaccines_rounded
                    : _type == CareItemType.visit
                    ? Icons.medical_services_rounded
                    : Icons.medication_rounded,
                message: range != null
                    ? 'در این بازه زمانی موردی برای فیلتر انتخابی وجود ندارد.'
                    : _search.text.trim().isEmpty
                    ? 'برای این فیلتر موردی وجود ندارد.'
                    : 'نتیجه‌ای برای «${localizeDigits(context, _search.text.trim())}» پیدا نشد.',
              )
            else
              for (final item in visible)
                Semantics(
                  button: item.type == CareItemType.medication,
                  label: item.type == CareItemType.medication
                      ? 'جزئیات ${item.title}'
                      : item.title,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: item.type == CareItemType.medication
                        ? () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  _TreatmentDetailsScreen(plan: item.raw),
                            ),
                          )
                        : null,
                    child: _CareHubCard(item: item),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
'''
text = regex_once(
    text,
    r"class _TreatmentsScreenState extends State<TreatmentsScreen> \{.*?\n\}\n\nclass _TypeChip",
    new_state + "\nclass _TypeChip",
    "treatments state replacement",
)
write(path, text)

# Source-level contract test for the treatments hub wiring. The shared CareItem
# tests above cover the actual filtering semantics.
path = "wellmate/test/treatments_round3_regression_test.dart"
write(
    path,
    r'''import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('treatments hub wires dose completion and date range filters', () {
    final source = File(
      'lib/screens/treatments/treatments_screen.dart',
    ).readAsStringSync();

    expect(source, contains('CareItem.fromDoseOccurrence'));
    expect(source, contains("CareItemStatusFilter.completed"));
    expect(source, contains("ValueKey('care-hub-date-range-filter')"));
    expect(source, contains('_loadBoundedRange'));
  });
}
''',
)


# ---------------------------------------------------------------------------
# 5) Home countdown: keep multiple upcoming items, including later injection.
# ---------------------------------------------------------------------------
path = "wellmate/lib/screens/home/home_screen_content.dart"
text = read(path)
text = replace_once(
    text,
    """  ScheduleItemModel? _nextOccurrence;""",
    """  List<ScheduleItemModel> _countdownOccurrences = const [];""",
    "home countdown field",
)
text = regex_once(
    text,
    r"      final actionable = allItems.*?      final nextOccurrence = future\.isNotEmpty\n          \? future\.first\n          : \(missedOccurrences\.isNotEmpty \? missedOccurrences\.first : null\);",
    """      final countdownOccurrences = selectHomeCountdownItems(\n        allItems,\n        DateTime.now(),\n      );""",
    "home countdown selection",
)
text = replace_once(
    text,
    """        _nextOccurrence = nextOccurrence;""",
    """        _countdownOccurrences = countdownOccurrences;""",
    "home countdown assignment",
)
text = replace_once(
    text,
    """        if (_nextOccurrence?.id == item.id) _nextOccurrence = null;""",
    """        _countdownOccurrences = _countdownOccurrences\n            .where((value) => value.id != item.id)\n            .toList(growable: false);""",
    "home countdown optimistic removal",
)
text = replace_once(
    text,
    """    final nextItem = _nextOccurrence;""",
    """    final countdownItems = _countdownOccurrences;""",
    "home countdown build variable",
)
old_card = r'''            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: nextItem == null
                  ? _TreatmentTimerPlaceholder(
                      hasTreatmentPlans: _hasTreatmentPlans,
                      onAction: _hasTreatmentPlans
                          ? widget.onOpenTreatments
                          : widget.onAddTreatment,
                      font: font,
                    )
                  : _buildNextOccurrenceCard(
                      item: nextItem,
                      font: font,
                      isPersian: isPersian,
                    ),
            ),'''
new_card = r'''            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: countdownItems.isEmpty
                  ? _TreatmentTimerPlaceholder(
                      hasTreatmentPlans: _hasTreatmentPlans,
                      onAction: _hasTreatmentPlans
                          ? widget.onOpenTreatments
                          : widget.onAddTreatment,
                      font: font,
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final cardWidth = countdownItems.length > 1
                            ? constraints.maxWidth * 0.92
                            : constraints.maxWidth;
                        return SingleChildScrollView(
                          key: const ValueKey('home-countdown-carousel'),
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          child: Row(
                            children: [
                              for (
                                var index = 0;
                                index < countdownItems.length;
                                index += 1
                              ) ...[
                                SizedBox(
                                  width: cardWidth,
                                  child: _buildNextOccurrenceCard(
                                    item: countdownItems[index],
                                    font: font,
                                    isPersian: isPersian,
                                  ),
                                ),
                                if (index < countdownItems.length - 1)
                                  const SizedBox(width: 12),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
            ),'''
text = replace_once(text, old_card, new_card, "home countdown carousel")
text = replace_once(
    text,
    """      return ActiveTreatmentCard(\n        treatmentName: item.title,""",
    """      return ActiveTreatmentCard(\n        key: ValueKey('home-countdown-${item.type}-${item.id}'),\n        treatmentName: item.title,""",
    "home medication countdown key",
)
# The second ActiveTreatmentCard is the visit/injection branch.
text = replace_once(
    text,
    """    return ActiveTreatmentCard(\n      treatmentName: item.title,""",
    """    final eventAccent = isAppointment\n        ? AppColors.careVisit\n        : AppColors.careInjection;\n    return ActiveTreatmentCard(\n      key: ValueKey('home-countdown-${item.type}-${item.id}'),\n      treatmentName: item.title,""",
    "home care countdown key and accent",
)
text = replace_once(
    text,
    """      assetIconPath: _getAssetPath(item.type),\n      progressValue: _progressValue(item),\n      secondsLeft: secondsLeft,\n      onTaken: null,""",
    """      assetIconPath: item.type == 'injection' ? null : _getAssetPath(item.type),\n      progressValue: _progressValue(item),\n      secondsLeft: secondsLeft,\n      onTaken: null,""",
    "home injection fallback icon",
)
text = replace_once(
    text,
    """      accentColor: isMissed ? missedColor : AppColors.primary,\n      progressColor: isMissed ? missedColor : AppColors.primaryLight,""",
    """      accentColor: isMissed ? missedColor : eventAccent,\n      progressColor: isMissed ? missedColor : eventAccent,""",
    "home semantic care countdown color",
)
helper = r'''

@visibleForTesting
List<ScheduleItemModel> selectHomeCountdownItems(
  Iterable<ScheduleItemModel> items,
  DateTime now, {
  int limit = 4,
}) {
  final actionable = items.where((item) {
    if (item.type == 'medicine') {
      return item.status == 'scheduled' || item.status == 'missed';
    }
    return item.status != 'completed' && item.status != 'cancelled';
  }).toList(growable: false);

  final future = actionable.where((item) {
    final scheduled = _homeCountdownScheduledDateTime(item);
    return scheduled != null && !scheduled.isBefore(now);
  }).toList()
    ..sort((left, right) {
      final l = _homeCountdownScheduledDateTime(left) ?? DateTime(2100);
      final r = _homeCountdownScheduledDateTime(right) ?? DateTime(2100);
      return l.compareTo(r);
    });

  if (future.isNotEmpty) return future.take(limit).toList(growable: false);

  final missed = actionable.where((item) => item.status == 'missed').toList()
    ..sort((left, right) {
      final l = _homeCountdownScheduledDateTime(left) ?? DateTime(2100);
      final r = _homeCountdownScheduledDateTime(right) ?? DateTime(2100);
      return l.compareTo(r);
    });
  return missed.take(1).toList(growable: false);
}

DateTime? _homeCountdownScheduledDateTime(ScheduleItemModel item) {
  if (item.scheduledAtUtc != null) return item.scheduledAtUtc!.toLocal();
  final date = item.startDate;
  final parts = item.time.split(':');
  if (date == null || parts.length < 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1].split(' ').first);
  if (hour == null || minute == null) return null;
  return DateTime(date.year, date.month, date.day, hour, minute);
}
'''
text = replace_once(
    text,
    "\nclass _TreatmentTimerPlaceholder extends StatelessWidget {",
    helper + "\nclass _TreatmentTimerPlaceholder extends StatelessWidget {",
    "home countdown selector helper",
)
write(path, text)

path = "wellmate/lib/screens/home/active_treatment_card.dart"
text = read(path)
text = replace_once(
    text,
    """  final String assetIconPath;""",
    """  final String? assetIconPath;""",
    "active treatment nullable asset",
)
old_image = r'''                        Image.asset(
                          assetIconPath,
                          width: 36,
                          height: 36,
                          errorBuilder: (_, __, ___) =>
                              Icon(fallbackIcon, color: accent),
                        ),'''
new_image = r'''                        if (assetIconPath?.trim().isNotEmpty == true)
                          Image.asset(
                            assetIconPath!,
                            width: 36,
                            height: 36,
                            errorBuilder: (_, __, ___) =>
                                Icon(fallbackIcon, color: accent),
                          )
                        else
                          Icon(fallbackIcon, color: accent, size: 36),'''
text = replace_once(text, old_image, new_image, "active treatment semantic fallback")
write(path, text)

path = "wellmate/test/home_injection_timeline_test.dart"
text = read(path)
text = replace_once(
    text,
    """import 'package:wellmate/screens/home/home_schedule_loader.dart';""",
    """import 'package:wellmate/models/schedule_item_model.dart';\nimport 'package:wellmate/screens/home/home_schedule_loader.dart';\nimport 'package:wellmate/screens/home/home_screen_content.dart';""",
    "home injection test imports",
)
insert = r'''

  test('countdown keeps injection when an earlier appointment also exists', () {
    final date = DateTime(2026, 8, 17);
    final items = [
      ScheduleItemModel(
        id: 'visit-1',
        title: 'چکاپ',
        time: '18:30',
        dosage: '',
        type: 'appointment',
        frequency: 'ویزیت',
        startDate: date,
      ),
      ScheduleItemModel(
        id: 'dose-1',
        title: 'دارو',
        time: '21:00',
        dosage: '۱ عدد',
        type: 'medicine',
        frequency: 'طبق برنامه',
        startDate: date,
      ),
      ScheduleItemModel(
        id: 'inj-1',
        title: 'B12',
        time: '21:30',
        dosage: '۱ آمپول',
        type: 'injection',
        frequency: 'تزریق',
        startDate: date,
      ),
    ];

    final countdown = selectHomeCountdownItems(
      items,
      DateTime(2026, 8, 17, 17),
    );
    expect(countdown.map((item) => item.id), ['visit-1', 'dose-1', 'inj-1']);
  });
'''
# Insert before the first closing brace of main, right before fake class.
text = replace_once(
    text,
    """  });\n}\n\nclass _InjectionSnapshotApi""",
    """  });""" + insert + "\n}\n\nclass _InjectionSnapshotApi",
    "home injection countdown test",
)
write(path, text)


# ---------------------------------------------------------------------------
# 6) Women Calendar dashboard order, large cycle ring, safe bottom sheet.
# ---------------------------------------------------------------------------
path = "wellmate/lib/screens/women_calendar/women_companion_screen.dart"
text = read(path)
old_order = r'''            _CycleOverviewCard(
              estimate: estimate,
              onOpenCalendar: _openAdvancedManagement,
            ),
            const SizedBox(height: 14),
            _DailyCheckInCard(
              log: _todayLog,
              saving: _saving,
              onEdit: () => _editDailyLog(DateTime.now()),
            ),
            const SizedBox(height: 14),
            _DailyTipCard(estimate: estimate, log: _todayLog),
            const SizedBox(height: 14),
            WomenCalendarMonthCard(
              episodes: _episodes,
              estimate: estimate,
              selectedDate: _selectedDate,
              onDateSelected: (date) => setState(() => _selectedDate = date),
            ),
            const SizedBox(height: 10),
            _SelectedDaySummaryCard(
              date: _selectedDate,
              log: _logForDate(_selectedDate),
              estimate: estimate,
              recordedBleeding: _isRecordedBleedingDay(_selectedDate),
              saving: _saving,
              onEdit: () => _editDailyLog(_selectedDate),
            ),
            const SizedBox(height: 14),
            _FourteenDayStrip(estimate: estimate),
            const SizedBox(height: 14),
            _ReportsCard(episodes: _episodes, logs: _dailyLogs),
            const SizedBox(height: 14),
            _ReminderAndSettingsCard(
              profile: _profile,
              onOpenSettings: _openAdvancedManagement,
            ),
            const SizedBox(height: 14),
            const _MedicalSafetyCard(),'''
new_order = r'''            _CycleOverviewCard(estimate: estimate),
            const SizedBox(height: 14),
            WomenCalendarMonthCard(
              episodes: _episodes,
              estimate: estimate,
              selectedDate: _selectedDate,
              onDateSelected: (date) => setState(() => _selectedDate = date),
            ),
            const SizedBox(height: 10),
            _SelectedDaySummaryCard(
              date: _selectedDate,
              log: _logForDate(_selectedDate),
              estimate: estimate,
              recordedBleeding: _isRecordedBleedingDay(_selectedDate),
              saving: _saving,
              onEdit: () => _editDailyLog(_selectedDate),
            ),
            const SizedBox(height: 14),
            _DailyCheckInCard(
              log: _todayLog,
              saving: _saving,
              onEdit: () => _editDailyLog(DateTime.now()),
            ),
            const SizedBox(height: 14),
            _DailyTipCard(estimate: estimate, log: _todayLog),
            const SizedBox(height: 14),
            _FourteenDayStrip(estimate: estimate),
            const SizedBox(height: 14),
            _ReportsCard(episodes: _episodes, logs: _dailyLogs),
            const SizedBox(height: 14),
            const _MedicalSafetyCard(),
            const SizedBox(height: 14),
            _ReminderAndSettingsCard(
              profile: _profile,
              onOpenSettings: _openAdvancedManagement,
            ),'''
text = replace_once(text, old_order, new_order, "women dashboard order")
new_cycle = r'''class _CycleOverviewCard extends StatelessWidget {
  const _CycleOverviewCard({required this.estimate});

  final WomenCalendarEstimate? estimate;

  @override
  Widget build(BuildContext context) {
    final value = estimate;
    final visual = phaseVisual(value?.detailedPhase);
    return _PastelCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final ringSize = math.min(constraints.maxWidth, 270.0);
          return Column(
            key: const ValueKey('women-cycle-overview-large'),
            children: [
              _CycleRing(estimate: value, size: ringSize),
              const SizedBox(height: 16),
              Text(
                visual.label,
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                  color: visual.foreground,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                value == null
                    ? 'برای نمایش چرخه، اطلاعات پایه را در تنظیمات کامل کن.'
                    : 'روز ${localizeDigits(context, value.cycleDay)} از چرخه ${localizeDigits(context, value.cycleLength)} روزه',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
              if (value != null) ...[
                const SizedBox(height: 5),
                Text(
                  '${localizeDigits(context, value.daysUntilNextPeriod)} روز تا شروع تخمینی دوره بعدی',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF866A80),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

'''
text = regex_once(
    text,
    r"class _CycleOverviewCard extends StatelessWidget \{.*?\n\}\n\nclass _CycleRing",
    new_cycle + "class _CycleRing",
    "women large cycle overview",
)
text = replace_once(
    text,
    """    final bottom = MediaQuery.viewInsetsOf(context).bottom;\n    return Container(""",
    """    final media = MediaQuery.of(context);\n    final bottom = math.max(media.viewInsets.bottom, media.viewPadding.bottom);\n    return Container(""",
    "women checkin bottom safe inset",
)
write(path, text)

path = "wellmate/test/women_companion_experience_test.dart"
text = read(path)
insert = r'''

  testWidgets('daily check-in submit stays above Android navigation inset', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(360, 780),
          viewPadding: EdgeInsets.only(bottom: 48),
        ),
        child: Provider<LifeMateApiClient>.value(
          value: _FakeLifeMateApiClient(),
          child: MaterialApp(
            locale: const Locale('fa'),
            home: Scaffold(
              body: WomenCompanionScreen(
                companionApi: _FakeWomenCompanionApi(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('ویرایش'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('ویرایش'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('ثبت حال امروز'),
      220,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();

    final buttonRect = tester.getRect(find.text('ثبت حال امروز'));
    expect(buttonRect.bottom, lessThanOrEqualTo(780 - 48));
    expect(tester.takeException(), isNull);
  }, skip: !LifeMateFeatureFlags.womenCalendarPilotEnabled);

  testWidgets('women dashboard puts large cycle then calendar before mood', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      Provider<LifeMateApiClient>.value(
        value: _FakeLifeMateApiClient(),
        child: MaterialApp(
          locale: const Locale('fa'),
          home: Scaffold(
            body: WomenCompanionScreen(
              companionApi: _FakeWomenCompanionApi(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('women-cycle-overview-large')),
      findsOneWidget,
    );
    expect(find.text('تقویم و ثبت دوره'), findsNothing);
  }, skip: !LifeMateFeatureFlags.womenCalendarPilotEnabled);
'''
# Insert tests before fake client class.
text = replace_once(
    text,
    "\n}\n\nclass _FakeLifeMateApiClient",
    insert + "\n}\n\nclass _FakeLifeMateApiClient",
    "women round3 widget tests",
)
write(path, text)

print('Round 3 physical QA patch applied successfully.')
