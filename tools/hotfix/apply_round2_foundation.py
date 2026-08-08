from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, content: str) -> None:
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding="utf-8")


def replace_once(path: str, old: str, new: str) -> None:
    text = read(path)
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{path}: expected exactly one match, found {count}: {old[:80]!r}")
    write(path, text.replace(old, new, 1))


def regex_once(path: str, pattern: str, replacement: str, flags=0) -> None:
    text = read(path)
    updated, count = re.subn(pattern, replacement, text, count=1, flags=flags)
    if count != 1:
        raise RuntimeError(f"{path}: regex expected exactly one match, found {count}: {pattern[:100]!r}")
    write(path, updated)


write(
    "packages/lifemate_client/lib/src/presentation_numbers.dart",
    r'''import 'package:flutter/widgets.dart';

/// Presentation-only number localization.
///
/// API payloads, IDs, DateTime values, persistence and logs must keep their
/// machine-readable representation. UI code can safely normalize user input
/// back to Latin digits before parsing.
abstract final class LifeMateNumbers {
  static const _latin = '0123456789';
  static const _persian = '۰۱۲۳۴۵۶۷۸۹';
  static const _arabicIndic = '٠١٢٣٤٥٦٧٨٩';

  static String toPersian(Object? value) {
    final input = value?.toString() ?? '';
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      final character = String.fromCharCode(rune);
      var index = _latin.indexOf(character);
      if (index < 0) index = _arabicIndic.indexOf(character);
      buffer.write(index < 0 ? character : _persian[index]);
    }
    return buffer.toString();
  }

  static String toLatin(Object? value) {
    final input = value?.toString() ?? '';
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      final character = String.fromCharCode(rune);
      var index = _persian.indexOf(character);
      if (index < 0) index = _arabicIndic.indexOf(character);
      buffer.write(index < 0 ? character : _latin[index]);
    }
    return buffer.toString();
  }

  static bool usesPersianDigits(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'fa';

  static String localize(BuildContext context, Object? value) =>
      usesPersianDigits(context) ? toPersian(value) : toLatin(value);

  static int? tryParseInt(Object? value) => int.tryParse(toLatin(value).trim());

  static double? tryParseDouble(Object? value) =>
      double.tryParse(toLatin(value).trim().replaceAll('٫', '.'));
}
''',
)

write(
    "packages/lifemate_client/lib/src/care_item.dart",
    r'''enum CareItemType { medication, visit, injection }

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
    final firstTime = schedules.isEmpty ? null : _text(schedules.first['localTime']);
    final startDate = DateTime.tryParse(_text(plan['startDate']) ?? '');
    final scheduledAt = _combine(startDate, firstTime);
    return CareItem(
      id: _text(plan['id']) ?? '',
      seriesId: _text(plan['id']),
      type: CareItemType.medication,
      title: name,
      subtitle: [dose, if (firstTime != null) firstTime]
          .where((value) => value.trim().isNotEmpty)
          .join(' • '),
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
    final title = _text(event['title']) ??
        (type == CareItemType.injection ? 'تزریق' : 'ویزیت');
    final date = DateTime.tryParse(_text(event['scheduledLocalDate']) ?? '');
    final time = _text(event['scheduledLocalTime']);
    final scheduledAt = DateTime.tryParse(_text(event['scheduledAtUtc']) ?? '')
            ?.toLocal() ??
        _combine(date, time);
    final provider = _text(event['providerName']) ?? '';
    final center = _text(event['centerName']) ?? '';
    final dose = _text(event['doseText']) ?? '';
    return CareItem(
      id: _text(event['id']) ?? '',
      seriesId: _text(event['seriesId']) ?? _text(event['id']),
      type: type,
      title: title,
      subtitle: [provider, dose, center, time ?? '']
          .where((value) => value.trim().isNotEmpty)
          .join(' • '),
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
    final items = source.where((item) {
      if (type != null && item.type != type) return false;
      final statusMatches = switch (status) {
        CareItemStatusFilter.all => true,
        CareItemStatusFilter.active => item.isActive,
        CareItemStatusFilter.upcoming => item.isUpcoming(reference),
        CareItemStatusFilter.completed => item.isCompleted,
      };
      if (!statusMatches) return false;
      return normalizedQuery.isEmpty || item.searchText.contains(normalizedQuery);
    }).toList(growable: false);

    int compareDate(CareItem left, CareItem right, {required bool newest}) {
      final l = left.scheduledAt;
      final r = right.scheduledAt;
      if (l == null && r == null) return left.title.compareTo(right.title);
      if (l == null) return 1;
      if (r == null) return -1;
      return newest ? r.compareTo(l) : l.compareTo(r);
    }

    final mutable = items.toList();
    mutable.sort((left, right) => switch (sort) {
      CareItemSort.nearest => compareDate(left, right, newest: false),
      CareItemSort.newest => compareDate(left, right, newest: true),
      CareItemSort.oldest => compareDate(left, right, newest: false),
      CareItemSort.name => left.title.compareTo(right.title),
      CareItemSort.type => left.type.index.compareTo(right.type.index),
    });
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
''',
)

write(
    "packages/lifemate_client/lib/src/app_notice.dart",
    r'''import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

enum LifeMateNoticeType { success, info, warning, error }

abstract final class LifeMateNotice {
  static OverlayEntry? _activeEntry;

  static void show(
    BuildContext context, {
    required String message,
    String? title,
    LifeMateNoticeType type = LifeMateNoticeType.info,
    Duration? duration,
  }) {
    _activeEntry?.remove();
    _activeEntry = null;
    final overlay = Overlay.of(context, rootOverlay: true);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _LifeMateNoticeOverlay(
        message: message,
        title: title,
        type: type,
        duration: duration ??
            (type == LifeMateNoticeType.error
                ? const Duration(seconds: 6)
                : const Duration(milliseconds: 3400)),
        onDismissed: () {
          if (entry.mounted) entry.remove();
          if (identical(_activeEntry, entry)) _activeEntry = null;
        },
      ),
    );
    _activeEntry = entry;
    overlay.insert(entry);
  }

  @visibleForTesting
  static void clearForTesting() {
    _activeEntry?.remove();
    _activeEntry = null;
  }
}

class _LifeMateNoticeOverlay extends StatefulWidget {
  const _LifeMateNoticeOverlay({
    required this.message,
    required this.title,
    required this.type,
    required this.duration,
    required this.onDismissed,
  });

  final String message;
  final String? title;
  final LifeMateNoticeType type;
  final Duration duration;
  final VoidCallback onDismissed;

  @override
  State<_LifeMateNoticeOverlay> createState() => _LifeMateNoticeOverlayState();
}

class _LifeMateNoticeOverlayState extends State<_LifeMateNoticeOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _timer;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 180),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final media = MediaQuery.maybeOf(context);
      final reduceMotion =
          media?.disableAnimations == true || media?.accessibleNavigation == true;
      if (reduceMotion) {
        _controller.value = 1;
      } else {
        _controller.forward();
      }
      _timer = Timer(widget.duration, _dismiss);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    if (_closing || !mounted) return;
    _closing = true;
    _timer?.cancel();
    final media = MediaQuery.maybeOf(context);
    final reduceMotion =
        media?.disableAnimations == true || media?.accessibleNavigation == true;
    if (!reduceMotion) await _controller.reverse();
    if (mounted) widget.onDismissed();
  }

  @override
  Widget build(BuildContext context) {
    final visual = _NoticeVisual.forType(widget.type);
    final top = MediaQuery.paddingOf(context).top + 10;
    final textDirection = Directionality.of(context);
    return Positioned(
      top: top,
      left: 16,
      right: 16,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: FadeTransition(
              opacity: CurvedAnimation(parent: _controller, curve: Curves.easeOut),
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, -0.22),
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
                ),
                child: Dismissible(
                  key: ValueKey('${widget.type}-${widget.message}'),
                  direction: DismissDirection.horizontal,
                  onDismissed: (_) => widget.onDismissed(),
                  child: Semantics(
                    liveRegion: true,
                    container: true,
                    label: [widget.title, widget.message]
                        .whereType<String>()
                        .join('، '),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.88),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: visual.color.withValues(alpha: 0.18),
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x16000000),
                                blurRadius: 26,
                                offset: Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Directionality(
                            textDirection: textDirection,
                            child: Padding(
                              padding: const EdgeInsetsDirectional.fromSTEB(
                                14,
                                12,
                                10,
                                12,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color: visual.color.withValues(alpha: 0.12),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      visual.icon,
                                      size: 21,
                                      color: visual.color,
                                    ),
                                  ),
                                  const SizedBox(width: 11),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (widget.title?.trim().isNotEmpty == true)
                                          Text(
                                            widget.title!,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w900,
                                              fontSize: 13.5,
                                              color: Color(0xFF253149),
                                            ),
                                          ),
                                        Text(
                                          widget.message,
                                          maxLines: 4,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            height: 1.45,
                                            fontSize: 12.5,
                                            color: Color(0xFF4E596B),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'بستن',
                                    onPressed: _dismiss,
                                    visualDensity: VisualDensity.compact,
                                    icon: const Icon(
                                      Icons.close_rounded,
                                      size: 19,
                                      color: Color(0xFF7B8492),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NoticeVisual {
  const _NoticeVisual(this.color, this.icon);

  final Color color;
  final IconData icon;

  static _NoticeVisual forType(LifeMateNoticeType type) => switch (type) {
        LifeMateNoticeType.success =>
          const _NoticeVisual(Color(0xFF16A978), Icons.check_circle_rounded),
        LifeMateNoticeType.info =>
          const _NoticeVisual(Color(0xFF4A90E2), Icons.info_rounded),
        LifeMateNoticeType.warning =>
          const _NoticeVisual(Color(0xFFE39A2D), Icons.warning_amber_rounded),
        LifeMateNoticeType.error =>
          const _NoticeVisual(Color(0xFFD95D66), Icons.error_rounded),
      };
}
''',
)

replace_once(
    "packages/lifemate_client/lib/lifemate_client.dart",
    "export 'src/capabilities.dart';\n",
    "export 'src/capabilities.dart';\nexport 'src/care_item.dart';\nexport 'src/app_notice.dart';\n",
)
replace_once(
    "packages/lifemate_client/lib/lifemate_client.dart",
    "export 'src/profile_avatar.dart';\n",
    "export 'src/profile_avatar.dart';\nexport 'src/presentation_numbers.dart';\n",
)

for path in [
    "wellmate/lib/core/utils/string_extensions.dart",
    "caremate/lib/core/utils/string_extensions.dart",
]:
    write(
        path,
        r'''import 'package:lifemate_client/lifemate_client.dart';

extension PersianNumberExtension on String {
  String toPersianDigit(bool isPersian) =>
      isPersian ? LifeMateNumbers.toPersian(this) : LifeMateNumbers.toLatin(this);

  String toLatinDigit() => LifeMateNumbers.toLatin(this);
}
''',
    )

replace_once(
    "wellmate/lib/core/utils/persian_date_utils.dart",
    "String localizeDigits(BuildContext context, Object? value) =>\n    (value?.toString() ?? '').toPersianDigit(usesPersianCalendar(context));",
    "String localizeDigits(BuildContext context, Object? value) =>\n    LifeMateNumbers.localize(context, value);",
)
replace_once(
    "wellmate/lib/core/utils/persian_date_utils.dart",
    "import 'package:shamsi_date/shamsi_date.dart';\n",
    "import 'package:shamsi_date/shamsi_date.dart';\nimport 'package:lifemate_client/lifemate_client.dart';\n",
)
replace_once(
    "caremate/lib/core/utils/persian_date_utils.dart",
    "String localizeDigits(BuildContext context, Object? value) =>\n    (value?.toString() ?? '').toPersianDigit(usesPersianCalendar(context));",
    "String localizeDigits(BuildContext context, Object? value) =>\n    LifeMateNumbers.localize(context, value);",
)
replace_once(
    "caremate/lib/core/utils/persian_date_utils.dart",
    "import 'package:shamsi_date/shamsi_date.dart';\n",
    "import 'package:shamsi_date/shamsi_date.dart';\nimport 'package:lifemate_client/lifemate_client.dart';\n",
)

# Form hierarchy: hint is visibly secondary, label sits between hint and value.
for path, primary in [
    ("wellmate/lib/main.dart", "AppColors.primary"),
    ("caremate/lib/main.dart", "AppColors.primaryBlue"),
]:
    marker = "          alignLabelWithHint: true,\n"
    addition = marker + "          hintStyle: const TextStyle(\n            color: Color(0xFF8B95A3),\n            fontWeight: FontWeight.w400,\n          ),\n          labelStyle: const TextStyle(\n            color: Color(0xFF667085),\n            fontWeight: FontWeight.w600,\n          ),\n          floatingLabelStyle: TextStyle(\n            color: " + primary + ",\n            fontWeight: FontWeight.w800,\n          ),\n"
    replace_once(path, marker, addition)

# Care item semantic color tokens. Existing aliases remain for compatibility.
replace_once(
    "wellmate/lib/core/theme/app_style.dart",
    "  static const Color calDotMedicine = Colors.pinkAccent;\n  static const Color calDotDoctor = Colors.blueAccent;\n  static const Color calDotTreatment = Colors.orangeAccent;",
    "  static const Color careMedication = Color(0xFFE95D8F);\n  static const Color careVisit = Color(0xFF4A90E2);\n  static const Color careInjection = Color(0xFFF2A43A);\n\n  static const Color calDotMedicine = careMedication;\n  static const Color calDotDoctor = careVisit;\n  static const Color calDotTreatment = careInjection;",
)

# Treatments becomes one domain-backed hub rather than a medication-only list.
regex_once(
    "wellmate/lib/screens/treatments/treatments_screen.dart",
    r"class TreatmentsScreen extends StatefulWidget \{.*?\n\}\n\nclass AddTreatmentScreen extends StatefulWidget",
    r'''class TreatmentsScreen extends StatefulWidget {
  const TreatmentsScreen({super.key, required this.refreshToken});

  final int refreshToken;

  @override
  State<TreatmentsScreen> createState() => _TreatmentsScreenState();
}

class _TreatmentsScreenState extends State<TreatmentsScreen> {
  final _search = TextEditingController();
  bool _loading = true;
  String? _error;
  List<CareItem> _items = const [];
  CareItemType? _type;
  CareItemStatusFilter _status = CareItemStatusFilter.all;
  CareItemSort _sort = CareItemSort.nearest;

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
      final results = await Future.wait<dynamic>([
        api.getTreatmentPlans(),
        // The care-event endpoint is intentionally bounded. A one-month window
        // keeps this hub fast while recurrence series are represented by the
        // occurrence returned inside the window.
        api.getCareEvents(
          fromDate: now.subtract(const Duration(days: 31)),
          toDate: now,
        ),
        api.getCareEvents(
          fromDate: now.add(const Duration(days: 1)),
          toDate: now.add(const Duration(days: 31)),
        ),
      ]);
      final plans = results[0] as List<Map<String, dynamic>>;
      final pastEvents = results[1] as List<Map<String, dynamic>>;
      final futureEvents = results[2] as List<Map<String, dynamic>>;
      final bySeries = <String, CareItem>{};
      for (final event in [...pastEvents, ...futureEvents]) {
        final item = CareItem.fromCareEvent(event);
        final key = item.seriesId ?? item.id;
        final previous = bySeries[key];
        if (previous == null ||
            (item.scheduledAt != null &&
                (previous.scheduledAt == null ||
                    item.scheduledAt!.isAfter(previous.scheduledAt!)))) {
          bySeries[key] = item;
        }
      }
      final items = <CareItem>[
        ...plans.map(CareItem.fromTreatmentPlan),
        ...bySeries.values,
      ];
      if (!mounted) return;
      setState(() => _items = List<CareItem>.unmodifiable(items));
    } catch (error) {
      debugPrint('WellMate care hub load failed: $error');
      if (mounted) setState(() => _error = 'درمان‌ها و برنامه‌های مراقبتی دریافت نشدند.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<CareItem> get _visible => CareItem.filterAndSort(
        _items,
        type: _type,
        status: _status,
        query: _search.text,
        sort: _sort,
      );

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    return RefreshIndicator(
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
                _TypeChip(label: 'همه', selected: _type == null, onTap: () => setState(() => _type = null)),
                _TypeChip(label: 'دارو', selected: _type == CareItemType.medication, onTap: () => setState(() => _type = CareItemType.medication)),
                _TypeChip(label: 'ویزیت', selected: _type == CareItemType.visit, onTap: () => setState(() => _type = CareItemType.visit)),
                _TypeChip(label: 'تزریق', selected: _type == CareItemType.injection, onTap: () => setState(() => _type = CareItemType.injection)),
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
                    DropdownMenuItem(value: CareItemStatusFilter.all, child: Text('همه وضعیت‌ها')),
                    DropdownMenuItem(value: CareItemStatusFilter.active, child: Text('فعال')),
                    DropdownMenuItem(value: CareItemStatusFilter.upcoming, child: Text('آینده')),
                    DropdownMenuItem(value: CareItemStatusFilter.completed, child: Text('تمام‌شده')),
                  ],
                  onChanged: (value) => setState(() => _status = value ?? _status),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<CareItemSort>(
                  key: const ValueKey('care-hub-sort'),
                  initialValue: _sort,
                  decoration: const InputDecoration(labelText: 'مرتب‌سازی'),
                  items: const [
                    DropdownMenuItem(value: CareItemSort.nearest, child: Text('نزدیک‌ترین')),
                    DropdownMenuItem(value: CareItemSort.newest, child: Text('جدیدترین')),
                    DropdownMenuItem(value: CareItemSort.oldest, child: Text('قدیمی‌ترین')),
                    DropdownMenuItem(value: CareItemSort.name, child: Text('نام')),
                    DropdownMenuItem(value: CareItemSort.type, child: Text('نوع')),
                  ],
                  onChanged: (value) => setState(() => _sort = value ?? _sort),
                ),
              ),
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
              message: _search.text.trim().isEmpty
                  ? 'برای این فیلتر موردی وجود ندارد.'
                  : 'نتیجه‌ای برای «${localizeDigits(context, _search.text.trim())}» پیدا نشد.',
            )
          else
            for (final item in visible) _CareHubCard(item: item),
        ],
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.only(end: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) => onTap(),
        ),
      );
}

class _CareHubCard extends StatelessWidget {
  const _CareHubCard({required this.item});
  final CareItem item;

  @override
  Widget build(BuildContext context) {
    final visual = switch (item.type) {
      CareItemType.medication => (Icons.medication_rounded, AppColors.careMedication, 'دارو'),
      CareItemType.visit => (Icons.medical_services_rounded, AppColors.careVisit, 'ویزیت'),
      CareItemType.injection => (Icons.vaccines_rounded, AppColors.careInjection, 'تزریق'),
    };
    final time = item.scheduledAt == null
        ? null
        : '${formatAppDate(context, item.scheduledAt!)} • ${formatAppTime(context, TimeOfDay.fromDateTime(item.scheduledAt!))}';
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: visual.$2.withValues(alpha: 0.12),
              child: Icon(visual.$1, color: visual.$2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          localizeDigits(context, item.title),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(visual.$3, style: TextStyle(color: visual.$2, fontSize: 11, fontWeight: FontWeight.w800)),
                    ],
                  ),
                  if (item.subtitle.trim().isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      localizeDigits(context, item.subtitle),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                  if (time != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      time,
                      style: TextStyle(color: visual.$2, fontSize: 12, fontWeight: FontWeight.w800),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AddTreatmentScreen extends StatefulWidget''',
    flags=re.S,
)

# Calendar marker semantic tokens already map injection to the warm token via alias;
# add animation semantics so selected/today are visually distinct and accessible.
replace_once(
    "wellmate/lib/screens/calendar/custom_table_calendar.dart",
    "      child: Material(\n        color: selected ? AppColors.primary : Colors.transparent,",
    "      child: AnimatedScale(\n        scale: selected ? 1.06 : 1,\n        duration: const Duration(milliseconds: 170),\n        curve: Curves.easeOutCubic,\n        child: Material(\n        color: selected ? AppColors.primary : Colors.transparent,",
)
replace_once(
    "wellmate/lib/screens/calendar/custom_table_calendar.dart",
    "        ),\n      ),\n    );\n  }\n}\n\nclass _EventDots",
    "        ),\n        ),\n      ),\n    );\n  }\n}\n\nclass _EventDots",
)

# Replace black/floating CRUD feedback in the most visible touched flows.
replace_once(
    "wellmate/lib/screens/treatments/care_event_form.dart",
    "      ScaffoldMessenger.of(context).showSnackBar(\n        SnackBar(\n          behavior: SnackBarBehavior.floating,\n          content: Text(\n            _isAppointment\n                ? 'ویزیت با موفقیت ثبت شد.'\n                : 'نوبت تزریق با موفقیت ثبت شد.',\n          ),\n        ),\n      );",
    "      LifeMateNotice.show(\n        context,\n        type: LifeMateNoticeType.success,\n        title: _isAppointment ? 'ویزیت ثبت شد' : 'تزریق ثبت شد',\n        message: _isAppointment\n            ? 'ویزیت با موفقیت به برنامه اضافه شد.'\n            : 'نوبت تزریق با موفقیت به برنامه اضافه شد.',\n      );",
)
replace_once(
    "wellmate/lib/screens/treatments/add_treatment_screen.dart",
    "      ScaffoldMessenger.of(context).showSnackBar(\n        const SnackBar(\n          content: Text('درمان ثبت شد و برنامه امروز به‌روزرسانی شد.'),\n          behavior: SnackBarBehavior.floating,\n        ),\n      );",
    "      LifeMateNotice.show(\n        context,\n        type: LifeMateNoticeType.success,\n        title: 'درمان ثبت شد',\n        message: 'برنامه درمان ذخیره شد و برنامه امروز به‌روزرسانی می‌شود.',\n      );",
)

# Tests for the new presentation/domain utilities and notice behavior.
write(
    "packages/lifemate_client/test/presentation_numbers_test.dart",
    r'''import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test('Persian digit formatting is presentation-only and reversible', () {
    expect(LifeMateNumbers.toPersian('1405/05/17 18:30 3/5'), '۱۴۰۵/۰۵/۱۷ ۱۸:۳۰ ۳/۵');
    expect(LifeMateNumbers.toLatin('۱۲۳٤٥'), '12345');
  });

  test('Persian and English numeric input parse safely', () {
    expect(LifeMateNumbers.tryParseInt('۱۲۳'), 123);
    expect(LifeMateNumbers.tryParseInt('123'), 123);
    expect(LifeMateNumbers.tryParseDouble('۳٫۵'), 3.5);
  });
}
''',
)

write(
    "packages/lifemate_client/test/care_item_test.dart",
    r'''import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  final medication = CareItem.fromTreatmentPlan({
    'id': 'med-1',
    'status': 'active',
    'doseText': '۱ عدد',
    'medication': {'name': 'ویتامین B'},
    'schedules': [{'localTime': '09:30'}],
  });
  final visit = CareItem.fromCareEvent({
    'id': 'visit-1',
    'eventType': 'appointment',
    'title': 'چکاپ زنان',
    'providerName': 'دکتر سارا راد',
    'centerName': 'مرکز الوند',
    'specialty': 'زنان',
    'scheduledLocalDate': '2026-08-17',
    'scheduledLocalTime': '18:30',
    'status': 'scheduled',
  });
  final injection = CareItem.fromCareEvent({
    'id': 'inj-1',
    'eventType': 'injection',
    'title': 'B12',
    'doseText': '۱ عدد',
    'centerName': 'درمانگاه',
    'scheduledLocalDate': '2026-08-17',
    'scheduledLocalTime': '21:30',
    'status': 'scheduled',
  });

  test('unified list contains medication visit and injection', () {
    expect({medication.type, visit.type, injection.type}, {
      CareItemType.medication,
      CareItemType.visit,
      CareItemType.injection,
    });
  });

  test('filter by type keeps injection', () {
    final result = CareItem.filterAndSort(
      [medication, visit, injection],
      type: CareItemType.injection,
    );
    expect(result.map((item) => item.title), ['B12']);
  });

  test('search indexes doctor and clinic', () {
    expect(CareItem.filterAndSort([visit], query: 'سارا'), hasLength(1));
    expect(CareItem.filterAndSort([visit], query: 'الوند'), hasLength(1));
  });

  test('search indexes medication and injection title', () {
    expect(CareItem.filterAndSort([medication], query: 'ویتامین'), hasLength(1));
    expect(CareItem.filterAndSort([injection], query: 'b12'), hasLength(1));
  });
}
''',
)

write(
    "packages/lifemate_client/test/app_notice_test.dart",
    r'''import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  tearDown(LifeMateNotice.clearForTesting);

  testWidgets('LifeMate notice appears in overlay and can be dismissed', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => LifeMateNotice.show(
                context,
                type: LifeMateNoticeType.success,
                message: 'ثبت شد',
              ),
              child: const Text('show'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('show'));
    await tester.pump();
    expect(find.text('ثبت شد'), findsOneWidget);
    await tester.tap(find.byTooltip('بستن'));
    await tester.pumpAndSettle();
    expect(find.text('ثبت شد'), findsNothing);
  });
}
''',
)

# Keep the one-shot applicator out of the resulting product commit.
Path(__file__).unlink()
workflow = ROOT / ".github/workflows/round2-foundation-one-shot.yml"
if workflow.exists():
    workflow.unlink()

print("round2 foundation applied")
