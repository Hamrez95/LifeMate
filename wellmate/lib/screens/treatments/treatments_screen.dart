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
        // The care-event endpoint is intentionally bounded. A one-month window
        // keeps this hub fast while recurrence series are represented by the
        // occurrence returned inside the window.
        safeLoad(
          api.getCareEvents(
            fromDate: now.subtract(const Duration(days: 31)),
            toDate: now,
          ),
          'past care events',
        ),
        safeLoad(
          api.getCareEvents(
            fromDate: now.add(const Duration(days: 1)),
            toDate: now.add(const Duration(days: 31)),
          ),
          'future care events',
        ),
      ]);
      final plans = results[0];
      final pastEvents = results[1];
      final futureEvents = results[2];
      if (failedSources == 3) {
        throw StateError('All treatment sources are unavailable.');
      }
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
      if (mounted)
        setState(() => _error = 'درمان‌ها و برنامه‌های مراقبتی دریافت نشدند.');
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
        'دارو',
      ),
      CareItemType.visit => (
        Icons.medical_services_rounded,
        AppColors.careVisit,
        'ویزیت',
      ),
      CareItemType.injection => (
        Icons.vaccines_rounded,
        AppColors.careInjection,
        'تزریق',
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
        const SnackBar(
          content: Text('درمان ثبت شد و برنامه امروز به‌روزرسانی می‌شود.'),
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
        setState(() => _error = 'ثبت درمان انجام نشد. اتصال را بررسی کنید.');
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
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 120),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'افزودن درمان روزانه',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            const Text(
              'نسخه MVP یک برنامه روزانه می‌سازد؛ بعداً می‌توانید الگوهای پیچیده‌تر اضافه کنید.',
            ),
            const SizedBox(height: 22),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'نام دارو',
                prefixIcon: Icon(Icons.medication_rounded),
                border: OutlineInputBorder(),
              ),
              validator: (value) => (value?.trim().isNotEmpty ?? false)
                  ? null
                  : 'نام دارو را وارد کنید.',
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _strength,
              decoration: const InputDecoration(
                labelText: 'قدرت دارو (اختیاری)',
                hintText: 'مثلاً ۵۰ میلی‌گرم',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _dose,
              decoration: const InputDecoration(
                labelText: 'مقدار مصرف',
                hintText: 'مثلاً یک قرص',
                border: OutlineInputBorder(),
              ),
              validator: (value) => (value?.trim().isNotEmpty ?? false)
                  ? null
                  : 'مقدار مصرف را وارد کنید.',
            ),
            const SizedBox(height: 14),
            InkWell(
              onTap: _busy ? null : _pickTime,
              borderRadius: BorderRadius.circular(12),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'زمان مصرف روزانه',
                  prefixIcon: Icon(Icons.schedule_rounded),
                  border: OutlineInputBorder(),
                ),
                child: Text(
                  timeLabel,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(fontSize: 17),
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _instructions,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'توضیحات (اختیاری)',
                hintText: 'مثلاً بعد از غذا',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: _busy ? null : _create,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_task_rounded),
                label: const Text('ثبت درمان'),
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
        return 'مشخصات دارو معتبر نیست.';
      case 'invalid_treatment_plan':
      case 'schedule_required':
        return 'برنامه درمان معتبر نیست.';
      default:
        return error.isUnauthorized
            ? 'نشست شما منقضی شده است؛ دوباره وارد شوید.'
            : 'ثبت درمان انجام نشد. دوباره تلاش کنید.';
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
              padding: const EdgeInsets.fromLTRB(12, 8, 20, 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'بازگشت',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_ios_new_rounded),
                  ),
                  const SizedBox(width: 4),
                  const Expanded(
                    child: Text(
                      'جزئیات درمان',
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
                    child: const Icon(
                      Icons.medication_rounded,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                children: [
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.shadowDark.withValues(alpha: 0.55),
                          blurRadius: 18,
                          offset: const Offset(0, 7),
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
                                  fallback: 'دارو',
                                ),
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.darkBlue,
                                ),
                              ),
                            ),
                            Chip(
                              label: Text(
                                status == 'active' ? 'فعال' : 'متوقف',
                              ),
                              side: BorderSide.none,
                              backgroundColor: status == 'active'
                                  ? AppColors.primary.withValues(alpha: 0.12)
                                  : Colors.grey.shade100,
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        _TreatmentInfoRow(
                          icon: Icons.science_outlined,
                          label: 'قدرت دارو',
                          value: _localizedText(
                            context,
                            medication['strengthText'],
                          ),
                        ),
                        _TreatmentInfoRow(
                          icon: Icons.medication_liquid_rounded,
                          label: 'مقدار مصرف',
                          value: _localizedText(context, plan['doseText']),
                        ),
                        _TreatmentInfoRow(
                          icon: Icons.notes_rounded,
                          label: 'دستور مصرف',
                          value: _localizedText(context, plan['instructions']),
                        ),
                        _TreatmentInfoRow(
                          icon: Icons.calendar_today_outlined,
                          label: 'تاریخ شروع',
                          value: _localizedDate(context, plan['startDate']),
                        ),
                        _TreatmentInfoRow(
                          icon: Icons.event_busy_outlined,
                          label: 'تاریخ پایان',
                          value: _localizedDate(
                            context,
                            plan['endDate'],
                            fallback: 'بدون پایان',
                          ),
                          showDivider: false,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'زمان‌های مصرف',
                    style: AppTextStyles.heading(
                      context,
                    ).copyWith(fontSize: 18),
                  ),
                  const SizedBox(height: 12),
                  if (schedules.isEmpty)
                    const _MessageCard(
                      icon: Icons.schedule_rounded,
                      message: 'زمانی برای این درمان ثبت نشده است.',
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
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.16),
                      ),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          color: AppColors.primary,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'ویرایش روزها، ساعت‌ها، یادآوری‌ها و وضعیت درمان با کنترل نسخه انجام می‌شود تا تغییرات هم‌زمان از بین نروند.',
                            style: TextStyle(height: 1.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const ValueKey('open-treatment-edit'),
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
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text(
                        'ویرایش درمان',
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

String _text(dynamic value, {String fallback = 'ثبت نشده'}) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? fallback : text;
}

String _localizedText(
  BuildContext context,
  dynamic value, {
  String fallback = 'ثبت نشده',
}) => localizeDigits(context, _text(value, fallback: fallback));

String _localizedDate(
  BuildContext context,
  dynamic value, {
  String fallback = 'ثبت نشده',
}) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) return fallback;
  final parsed = DateTime.tryParse(text);
  return parsed == null
      ? localizeDigits(context, text)
      : formatAppDate(context, parsed);
}

String _weekdayLabel(String? value) => switch (value) {
  'saturday' => 'شنبه',
  'sunday' => 'یکشنبه',
  'monday' => 'دوشنبه',
  'tuesday' => 'سه‌شنبه',
  'wednesday' => 'چهارشنبه',
  'thursday' => 'پنجشنبه',
  'friday' => 'جمعه',
  _ => value ?? 'روز ثبت نشده',
};
