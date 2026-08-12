import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_style.dart';
import '../../core/utils/persian_date_utils.dart';
import 'edit_treatment_screen.dart';

class TreatmentsScreen extends StatefulWidget {
  const TreatmentsScreen({super.key, required this.refreshToken});

  final int refreshToken;

  @override
  State<TreatmentsScreen> createState() => _TreatmentsScreenState();
}

class _TreatmentsScreenState extends State<TreatmentsScreen> {
  final _search = TextEditingController();
  bool _loading = true;
  bool _backgroundRefreshing = false;
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
        final hasData =
            _planItems.isNotEmpty ||
            _careEventItems.isNotEmpty ||
            _doseItems.isNotEmpty;
        if (hasData) {
          _backgroundRefreshing = true;
        } else {
          _loading = true;
        }
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
        setState(
          () => _error = LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'درمان‌ها و برنامه‌های مراقبتی دریافت نشدند.',
              en: "Treatments and care plans were not received.",
            ),
            en: "Treatments and care plans were not received.",
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _backgroundRefreshing = false;
        });
      }
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
      initialDate: current?.start ?? today.subtract(Duration(days: 7)),
      firstDate: DateTime(2020),
      lastDate: today.add(Duration(days: 730)),
      title: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(fa: 'از تاریخ', en: "From history"),
        en: "From history",
      ),
    );
    if (start == null || !mounted) return;
    final initialEnd = current?.end != null && !current!.end.isBefore(start)
        ? current.end
        : start;
    final end = await showAppDatePicker(
      context: context,
      initialDate: initialEnd,
      firstDate: start,
      lastDate: today.add(Duration(days: 730)),
      title: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(fa: 'تا تاریخ', en: "to date"),
        en: "to date",
      ),
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
          key: ValueKey('wellmate-unified-care-hub'),
          physics: AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(20, 24, 20, 120),
          children: [
            if (_backgroundRefreshing) ...[
              LinearProgressIndicator(minHeight: 2),
              SizedBox(height: 10),
            ],
            Text(
              LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'درمان‌های من',
                  en: "My treatments",
                ),
                en: "My treatments",
              ),
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            SizedBox(height: 6),
            Text(
              LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'دارو، ویزیت و تزریق در یک نمای قابل جست‌وجو و مرتب‌سازی.',
                  en: "Medicines, visits and injections in a searchable and sortable view.",
                ),
                en: "Medicines, visits and injections in a searchable and sortable view.",
              ),
              style: TextStyle(color: AppColors.textSecondary),
            ),
            SizedBox(height: 16),
            TextField(
              key: ValueKey('care-hub-search'),
              controller: _search,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'جست‌وجو در نام، پزشک، درمانگاه، آدرس یا توضیحات',
                    en: "Search by name, doctor, clinic, address or description",
                  ),
                  en: "Search by name, doctor, clinic, address or description",
                ),
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
            SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _TypeChip(
                    label: LifeMateRuntimeLocale.select(
                      fa: LifeMateRuntimeLocale.select(
                        fa: 'همه',
                        en: "everyone",
                      ),
                      en: "everyone",
                    ),
                    selected: _type == null,
                    onTap: () => setState(() => _type = null),
                  ),
                  _TypeChip(
                    label: LifeMateRuntimeLocale.select(
                      fa: LifeMateRuntimeLocale.select(
                        fa: 'دارو',
                        en: "Medication",
                      ),
                      en: "medicine",
                    ),
                    selected: _type == CareItemType.medication,
                    onTap: () =>
                        setState(() => _type = CareItemType.medication),
                  ),
                  _TypeChip(
                    label: LifeMateRuntimeLocale.select(
                      fa: LifeMateRuntimeLocale.select(
                        fa: 'ویزیت',
                        en: "Appointment",
                      ),
                      en: "visit",
                    ),
                    selected: _type == CareItemType.visit,
                    onTap: () => setState(() => _type = CareItemType.visit),
                  ),
                  _TypeChip(
                    label: LifeMateRuntimeLocale.select(
                      fa: LifeMateRuntimeLocale.select(
                        fa: 'تزریق',
                        en: "Injection",
                      ),
                      en: "Injection",
                    ),
                    selected: _type == CareItemType.injection,
                    onTap: () => setState(() => _type = CareItemType.injection),
                  ),
                ],
              ),
            ),
            SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<CareItemStatusFilter>(
                    key: ValueKey('care-hub-status-filter'),
                    initialValue: _status,
                    decoration: InputDecoration(
                      labelText: LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'وضعیت',
                          en: "status",
                        ),
                        en: "status",
                      ),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: CareItemStatusFilter.all,
                        child: Text(
                          LifeMateRuntimeLocale.select(
                            fa: LifeMateRuntimeLocale.select(
                              fa: 'همه وضعیت‌ها',
                              en: "All situations",
                            ),
                            en: "All situations",
                          ),
                        ),
                      ),
                      DropdownMenuItem(
                        value: CareItemStatusFilter.active,
                        child: Text(
                          LifeMateRuntimeLocale.select(
                            fa: LifeMateRuntimeLocale.select(
                              fa: 'فعال',
                              en: "active",
                            ),
                            en: "active",
                          ),
                        ),
                      ),
                      DropdownMenuItem(
                        value: CareItemStatusFilter.upcoming,
                        child: Text(
                          LifeMateRuntimeLocale.select(
                            fa: LifeMateRuntimeLocale.select(
                              fa: 'آینده',
                              en: "the future",
                            ),
                            en: "the future",
                          ),
                        ),
                      ),
                      DropdownMenuItem(
                        value: CareItemStatusFilter.completed,
                        child: Text(
                          LifeMateRuntimeLocale.select(
                            fa: LifeMateRuntimeLocale.select(
                              fa: 'تمام‌شده',
                              en: "finished",
                            ),
                            en: "finished",
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _status = value ?? _status),
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<CareItemSort>(
                    key: ValueKey('care-hub-sort'),
                    initialValue: _sort,
                    decoration: InputDecoration(
                      labelText: LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'مرتب‌سازی',
                          en: "sorting",
                        ),
                        en: "sorting",
                      ),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: CareItemSort.nearest,
                        child: Text(
                          LifeMateRuntimeLocale.select(
                            fa: LifeMateRuntimeLocale.select(
                              fa: 'نزدیک‌ترین',
                              en: "the closest",
                            ),
                            en: "the closest",
                          ),
                        ),
                      ),
                      DropdownMenuItem(
                        value: CareItemSort.newest,
                        child: Text(
                          LifeMateRuntimeLocale.select(
                            fa: LifeMateRuntimeLocale.select(
                              fa: 'جدیدترین',
                              en: "The newest",
                            ),
                            en: "The newest",
                          ),
                        ),
                      ),
                      DropdownMenuItem(
                        value: CareItemSort.oldest,
                        child: Text(
                          LifeMateRuntimeLocale.select(
                            fa: LifeMateRuntimeLocale.select(
                              fa: 'قدیمی‌ترین',
                              en: "the oldest",
                            ),
                            en: "the oldest",
                          ),
                        ),
                      ),
                      DropdownMenuItem(
                        value: CareItemSort.name,
                        child: Text(
                          LifeMateRuntimeLocale.select(
                            fa: LifeMateRuntimeLocale.select(
                              fa: 'نام',
                              en: "name",
                            ),
                            en: "name",
                          ),
                        ),
                      ),
                      DropdownMenuItem(
                        value: CareItemSort.type,
                        child: Text(
                          LifeMateRuntimeLocale.select(
                            fa: LifeMateRuntimeLocale.select(
                              fa: 'نوع',
                              en: "type",
                            ),
                            en: "type",
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _sort = value ?? _sort),
                  ),
                ),
              ],
            ),
            SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: ValueKey('care-hub-date-range-filter'),
                    onPressed: _loading ? null : _pickDateRange,
                    icon: Icon(Icons.date_range_rounded),
                    label: Text(
                      range == null
                          ? LifeMateRuntimeLocale.select(
                              fa: LifeMateRuntimeLocale.select(
                                fa: 'بازه زمانی',
                                en: "time frame",
                              ),
                              en: "time frame",
                            )
                          : LifeMateRuntimeLocale.select(
                              fa: LifeMateRuntimeLocale.select(
                                fa: '${formatAppDate(context, range.start)} تا ${formatAppDate(context, range.end)}',
                                en: "${formatAppDate(context, range.start)} to ${formatAppDate(context, range.end)}",
                              ),
                              en: "${formatAppDate(context, range.start)} to ${formatAppDate(context, range.end)}",
                            ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                if (range != null) ...[
                  SizedBox(width: 6),
                  IconButton(
                    key: ValueKey('care-hub-clear-date-range'),
                    tooltip: LifeMateRuntimeLocale.select(
                      fa: LifeMateRuntimeLocale.select(
                        fa: 'حذف بازه زمانی',
                        en: "Remove time frame",
                      ),
                      en: "Remove time frame",
                    ),
                    onPressed: _loading ? null : _clearDateRange,
                    icon: Icon(Icons.close_rounded),
                  ),
                ],
              ],
            ),
            SizedBox(height: 18),
            if (_loading && visible.isEmpty)
              Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _MessageCard(
                icon: Icons.cloud_off_rounded,
                message: _error!,
                actionLabel: LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'تلاش دوباره',
                    en: "Try again",
                  ),
                  en: "Try again",
                ),
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
                    ? LifeMateRuntimeLocale.select(
                        fa: 'برای این فیلتر موردی وجود ندارد.',
                        en: "There are no items for this filter.",
                      )
                    : 'نتیجه‌ای برای «${localizeDigits(context, _search.text.trim())}» پیدا نشد.',
              )
            else
              for (final item in visible)
                Semantics(
                  button: item.type == CareItemType.medication,
                  label: item.type == CareItemType.medication
                      ? LifeMateRuntimeLocale.select(
                          fa: LifeMateRuntimeLocale.select(
                            fa: 'جزئیات ${item.title}',
                            en: "${item.title} details",
                          ),
                          en: "${item.title} details",
                        )
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

class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
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
      CareItemType.medication => (
        Icons.medication_rounded,
        AppColors.careMedication,
        LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(fa: 'دارو', en: "Medication"),
          en: "medicine",
        ),
      ),
      CareItemType.visit => (
        Icons.medical_services_rounded,
        AppColors.careVisit,
        LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(fa: 'ویزیت', en: "Appointment"),
          en: "visit",
        ),
      ),
      CareItemType.injection => (
        Icons.vaccines_rounded,
        AppColors.careInjection,
        LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(fa: 'تزریق', en: "Injection"),
          en: "Injection",
        ),
      ),
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
                      Text(
                        visual.$3,
                        style: TextStyle(
                          color: visual.$2,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
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
                      style: TextStyle(
                        color: visual.$2,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
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

class AddTreatmentScreen extends StatefulWidget {
  const AddTreatmentScreen({super.key, required this.onCreated});

  final VoidCallback onCreated;

  @override
  State<AddTreatmentScreen> createState() => _AddTreatmentScreenState();
}

class _AddTreatmentScreenState extends State<AddTreatmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _strength = TextEditingController();
  final _dose = TextEditingController();
  final _instructions = TextEditingController();
  TimeOfDay _time = TimeOfDay.now();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _strength.dispose();
    _dose.dispose();
    _instructions.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final value = await showTimePicker(context: context, initialTime: _time);
    if (value != null && mounted) setState(() => _time = value);
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = context.read<LifeMateApiClient>();
      final medication = await api.createMedication(
        name: _name.text,
        strengthText: _strength.text,
        form: 'tablet',
      );
      final localTime =
          '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}';
      const week = [
        'sunday',
        'monday',
        'tuesday',
        'wednesday',
        'thursday',
        'friday',
        'saturday',
      ];
      await api.createTreatmentPlan(
        medicationId: medication['id'].toString(),
        doseText: _dose.text,
        instructions: _instructions.text,
        startDate: DateTime.now(),
        timeZone: 'Asia/Tehran',
        schedules: [
          for (final day in week) {'dayOfWeek': day, 'localTime': localTime},
        ],
      );
      if (!mounted) return;
      _name.clear();
      _strength.clear();
      _dose.clear();
      _instructions.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'درمان ثبت شد و برنامه امروز به‌روزرسانی می‌شود.',
                en: "The treatment was recorded and the program will be updated today.",
              ),
              en: "The treatment was recorded and the program will be updated today.",
            ),
          ),
        ),
      );
      widget.onCreated();
    } on LifeMateApiException catch (error) {
      if (mounted) {
        setState(() => _error = _friendlyError(error));
      }
    } catch (error) {
      debugPrint('WellMate treatment creation failed: $error');
      if (mounted) {
        setState(
          () => _error = LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'ثبت درمان انجام نشد. اتصال را بررسی کنید.',
              en: "The treatment was not recorded. Check the connection.",
            ),
            en: "The treatment was not recorded. Check the connection.",
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final timeLabel =
        '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}';
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 24, 20, 120),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'افزودن درمان روزانه',
                  en: "Add daily treatment",
                ),
                en: "Add daily treatment",
              ),
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 6),
            Text(
              LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'نسخه MVP یک برنامه روزانه می‌سازد؛ بعداً می‌توانید الگوهای پیچیده‌تر اضافه کنید.',
                  en: "The MVP version creates a daily schedule; You can add more complex patterns later.",
                ),
                en: "The MVP version creates a daily schedule; You can add more complex patterns later.",
              ),
            ),
            SizedBox(height: 22),
            TextFormField(
              controller: _name,
              decoration: InputDecoration(
                labelText: LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'نام دارو',
                    en: "name of the drug",
                  ),
                  en: "name of the drug",
                ),
                prefixIcon: Icon(Icons.medication_rounded),
                border: OutlineInputBorder(),
              ),
              validator: (value) => (value?.trim().isNotEmpty ?? false)
                  ? null
                  : LifeMateRuntimeLocale.select(
                      fa: LifeMateRuntimeLocale.select(
                        fa: 'نام دارو را وارد کنید.',
                        en: "Enter the name of the drug.",
                      ),
                      en: "Enter the name of the drug.",
                    ),
            ),
            SizedBox(height: 14),
            TextFormField(
              controller: _strength,
              decoration: InputDecoration(
                labelText: LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'قدرت دارو (اختیاری)',
                    en: "potion strength (optional)",
                  ),
                  en: "potion strength (optional)",
                ),
                hintText: LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'مثلاً ۵۰ میلی‌گرم',
                    en: "For example, 50 mg",
                  ),
                  en: "For example, 50 mg",
                ),
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 14),
            TextFormField(
              controller: _dose,
              decoration: InputDecoration(
                labelText: LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'مقدار مصرف',
                    en: "Consumption amount",
                  ),
                  en: "Consumption amount",
                ),
                hintText: LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'مثلاً یک قرص',
                    en: "For example, a pill",
                  ),
                  en: "For example, a pill",
                ),
                border: OutlineInputBorder(),
              ),
              validator: (value) => (value?.trim().isNotEmpty ?? false)
                  ? null
                  : LifeMateRuntimeLocale.select(
                      fa: LifeMateRuntimeLocale.select(
                        fa: 'مقدار مصرف را وارد کنید.',
                        en: "Enter the consumption amount.",
                      ),
                      en: "Enter the consumption amount.",
                    ),
            ),
            SizedBox(height: 14),
            InkWell(
              onTap: _busy ? null : _pickTime,
              borderRadius: BorderRadius.circular(12),
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'زمان مصرف روزانه',
                      en: "Daily use time",
                    ),
                    en: "Daily use time",
                  ),
                  prefixIcon: Icon(Icons.schedule_rounded),
                  border: OutlineInputBorder(),
                ),
                child: Text(
                  timeLabel,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(fontSize: 17),
                ),
              ),
            ),
            SizedBox(height: 14),
            TextFormField(
              controller: _instructions,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'توضیحات (اختیاری)',
                    en: "Description (optional)",
                  ),
                  en: "Description (optional)",
                ),
                hintText: LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'مثلاً بعد از غذا',
                    en: "For example, after a meal",
                  ),
                  en: "For example, after a meal",
                ),
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              SizedBox(height: 14),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: _busy ? null : _create,
                icon: _busy
                    ? SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(Icons.add_task_rounded),
                label: Text(
                  LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'ثبت درمان',
                      en: "Treatment registration",
                    ),
                    en: "Treatment registration",
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _friendlyError(LifeMateApiException error) {
    switch (error.code) {
      case 'invalid_medication':
      case 'invalid_name':
        return LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'مشخصات دارو معتبر نیست.',
            en: "The drug specification is not valid.",
          ),
          en: "The drug specification is not valid.",
        );
      case 'invalid_treatment_plan':
      case 'schedule_required':
        return LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'برنامه درمان معتبر نیست.',
            en: "The treatment plan is not valid.",
          ),
          en: "The treatment plan is not valid.",
        );
      default:
        return error.isUnauthorized
            ? LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'نشست شما منقضی شده است؛ دوباره وارد شوید.',
                  en: "Your session has expired; Sign in again.",
                ),
                en: "Your session has expired; Sign in again.",
              )
            : LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'ثبت درمان انجام نشد. دوباره تلاش کنید.',
                  en: "The treatment was not registered. Try again.",
                ),
                en: "The treatment was not registered. Try again.",
              );
    }
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            Icon(icon, size: 48, color: AppColors.primary),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (actionLabel != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class _TreatmentDetailsScreen extends StatelessWidget {
  const _TreatmentDetailsScreen({required this.plan});

  final Map<String, dynamic> plan;

  @override
  Widget build(BuildContext context) {
    final medication = plan['medication'] as Map<String, dynamic>? ?? const {};
    final schedules = plan['schedules'] as List<dynamic>? ?? const [];
    final status = plan['status']?.toString() ?? 'unknown';
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(12, 8, 20, 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: LifeMateRuntimeLocale.select(
                      fa: LifeMateRuntimeLocale.select(
                        fa: 'بازگشت',
                        en: "Back",
                      ),
                      en: "return",
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.arrow_back_ios_new_rounded),
                  ),
                  SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'جزئیات درمان',
                          en: "Treatment details",
                        ),
                        en: "Treatment details",
                      ),
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                        color: AppColors.darkBlue,
                      ),
                    ),
                  ),
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.medication_rounded,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(24, 16, 24, 32),
                children: [
                  Container(
                    padding: EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.shadowDark.withValues(alpha: 0.55),
                          blurRadius: 18,
                          offset: Offset(0, 7),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _localizedText(
                                  context,
                                  medication['name'],
                                  fallback: LifeMateRuntimeLocale.select(
                                    fa: LifeMateRuntimeLocale.select(
                                      fa: 'دارو',
                                      en: "Medication",
                                    ),
                                    en: "medicine",
                                  ),
                                ),
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.darkBlue,
                                ),
                              ),
                            ),
                            Chip(
                              label: Text(
                                status == 'active'
                                    ? LifeMateRuntimeLocale.select(
                                        fa: LifeMateRuntimeLocale.select(
                                          fa: 'فعال',
                                          en: "active",
                                        ),
                                        en: "active",
                                      )
                                    : LifeMateRuntimeLocale.select(
                                        fa: LifeMateRuntimeLocale.select(
                                          fa: 'متوقف',
                                          en: "stopped",
                                        ),
                                        en: "stopped",
                                      ),
                              ),
                              side: BorderSide.none,
                              backgroundColor: status == 'active'
                                  ? AppColors.primary.withValues(alpha: 0.12)
                                  : Colors.grey.shade100,
                            ),
                          ],
                        ),
                        SizedBox(height: 18),
                        _TreatmentInfoRow(
                          icon: Icons.science_outlined,
                          label: LifeMateRuntimeLocale.select(
                            fa: LifeMateRuntimeLocale.select(
                              fa: 'قدرت دارو',
                              en: "The power of medicine",
                            ),
                            en: "The power of medicine",
                          ),
                          value: _localizedText(
                            context,
                            medication['strengthText'],
                          ),
                        ),
                        _TreatmentInfoRow(
                          icon: Icons.medication_liquid_rounded,
                          label: LifeMateRuntimeLocale.select(
                            fa: LifeMateRuntimeLocale.select(
                              fa: 'مقدار مصرف',
                              en: "Consumption amount",
                            ),
                            en: "Consumption amount",
                          ),
                          value: _localizedText(context, plan['doseText']),
                        ),
                        _TreatmentInfoRow(
                          icon: Icons.notes_rounded,
                          label: LifeMateRuntimeLocale.select(
                            fa: LifeMateRuntimeLocale.select(
                              fa: 'دستور مصرف',
                              en: "Instructions for use",
                            ),
                            en: "Instructions for use",
                          ),
                          value: _localizedText(context, plan['instructions']),
                        ),
                        _TreatmentInfoRow(
                          icon: Icons.calendar_today_outlined,
                          label: LifeMateRuntimeLocale.select(
                            fa: LifeMateRuntimeLocale.select(
                              fa: 'تاریخ شروع',
                              en: "start date",
                            ),
                            en: "start date",
                          ),
                          value: _localizedDate(context, plan['startDate']),
                        ),
                        _TreatmentInfoRow(
                          icon: Icons.event_busy_outlined,
                          label: LifeMateRuntimeLocale.select(
                            fa: LifeMateRuntimeLocale.select(
                              fa: 'تاریخ پایان',
                              en: "end date",
                            ),
                            en: "end date",
                          ),
                          value: _localizedDate(
                            context,
                            plan['endDate'],
                            fallback: LifeMateRuntimeLocale.select(
                              fa: LifeMateRuntimeLocale.select(
                                fa: 'بدون پایان',
                                en: "no end",
                              ),
                              en: "no end",
                            ),
                          ),
                          showDivider: false,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 18),
                  Text(
                    LifeMateRuntimeLocale.select(
                      fa: LifeMateRuntimeLocale.select(
                        fa: 'زمان‌های مصرف',
                        en: "Consumption times",
                      ),
                      en: "Consumption times",
                    ),
                    style: AppTextStyles.heading(
                      context,
                    ).copyWith(fontSize: 18),
                  ),
                  SizedBox(height: 12),
                  if (schedules.isEmpty)
                    _MessageCard(
                      icon: Icons.schedule_rounded,
                      message: LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'زمانی برای این درمان ثبت نشده است.',
                          en: "No time has been recorded for this treatment.",
                        ),
                        en: "No time has been recorded for this treatment.",
                      ),
                    )
                  else
                    ...schedules.map((schedule) {
                      final value = schedule as Map<String, dynamic>;
                      final rawTime = value['localTime']?.toString() ?? '';
                      final time = rawTime.length >= 5
                          ? rawTime.substring(0, 5)
                          : _text(rawTime);
                      return Card(
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          leading: const Icon(
                            Icons.schedule_rounded,
                            color: AppColors.primary,
                          ),
                          title: Text(
                            localizeDigits(context, time),
                            textDirection: TextDirection.ltr,
                          ),
                          subtitle: Text(
                            _weekdayLabel(value['dayOfWeek']?.toString()),
                          ),
                        ),
                      );
                    }),
                  SizedBox(height: 18),
                  Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.16),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          color: AppColors.primary,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            LifeMateRuntimeLocale.select(
                              fa: LifeMateRuntimeLocale.select(
                                fa: 'ویرایش روزها، ساعت‌ها، یادآوری‌ها و وضعیت درمان با کنترل نسخه انجام می‌شود تا تغییرات هم‌زمان از بین نروند.',
                                en: "Editing of days, hours, reminders and treatment status is done with version control so that changes are not lost at the same time.",
                              ),
                              en: "Editing of days, hours, reminders and treatment status is done with version control so that changes are not lost at the same time.",
                            ),
                            style: TextStyle(height: 1.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: ValueKey('open-treatment-edit'),
                      onPressed: () async {
                        final changed = await Navigator.of(context).push<bool>(
                          MaterialPageRoute<bool>(
                            builder: (_) => EditTreatmentScreen(plan: plan),
                          ),
                        );
                        if (changed == true && context.mounted) {
                          Navigator.of(context).pop(true);
                        }
                      },
                      icon: Icon(Icons.edit_outlined),
                      label: Text(
                        LifeMateRuntimeLocale.select(
                          fa: LifeMateRuntimeLocale.select(
                            fa: 'ویرایش درمان',
                            en: "Editing treatment",
                          ),
                          en: "Editing treatment",
                        ),
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TreatmentInfoRow extends StatelessWidget {
  const _TreatmentInfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.showDivider = true,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Row(
            children: [
              Icon(icon, size: 21, color: AppColors.primaryBlue),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (showDivider) const Divider(height: 1),
      ],
    );
  }
}

String _text(dynamic value, {String? fallback}) {
  final text = value?.toString().trim();
  final emptyValue =
      fallback ??
      LifeMateRuntimeLocale.select(fa: 'ثبت نشده', en: 'Not recorded');
  return text == null || text.isEmpty ? emptyValue : text;
}

String _localizedText(
  BuildContext context,
  dynamic value, {
  String? fallback,
}) => localizeDigits(context, _text(value, fallback: fallback));

String _localizedDate(BuildContext context, dynamic value, {String? fallback}) {
  final text = value?.toString().trim();
  final emptyValue =
      fallback ??
      LifeMateRuntimeLocale.select(fa: 'ثبت نشده', en: 'Not recorded');
  if (text == null || text.isEmpty) return emptyValue;
  final parsed = DateTime.tryParse(text);
  return parsed == null
      ? localizeDigits(context, text)
      : formatAppDate(context, parsed);
}

String _weekdayLabel(String? value) => switch (value) {
  'saturday' => LifeMateRuntimeLocale.select(
    fa: LifeMateRuntimeLocale.select(fa: 'شنبه', en: "Saturday"),
    en: "Saturday",
  ),
  'sunday' => LifeMateRuntimeLocale.select(
    fa: LifeMateRuntimeLocale.select(fa: 'یکشنبه', en: "Sunday"),
    en: "Sunday",
  ),
  'monday' => LifeMateRuntimeLocale.select(
    fa: LifeMateRuntimeLocale.select(fa: 'دوشنبه', en: "Monday"),
    en: "Monday",
  ),
  'tuesday' => LifeMateRuntimeLocale.select(
    fa: LifeMateRuntimeLocale.select(fa: 'سه‌شنبه', en: "Tuesday"),
    en: "Tuesday",
  ),
  'wednesday' => LifeMateRuntimeLocale.select(
    fa: LifeMateRuntimeLocale.select(fa: 'چهارشنبه', en: "Wednesday"),
    en: "Wednesday",
  ),
  'thursday' => LifeMateRuntimeLocale.select(
    fa: LifeMateRuntimeLocale.select(fa: 'پنجشنبه', en: "Thursday"),
    en: "Thursday",
  ),
  'friday' => LifeMateRuntimeLocale.select(
    fa: LifeMateRuntimeLocale.select(fa: 'جمعه', en: "Friday"),
    en: "Friday",
  ),
  _ =>
    value ??
        LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'روز ثبت نشده',
            en: "Unregistered day",
          ),
          en: "Unregistered day",
        ),
};
