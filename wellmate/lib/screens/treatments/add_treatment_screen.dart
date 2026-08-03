import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_style.dart';
import 'treatment_schedule_payload.dart';

class TabbedAddTreatmentScreen extends StatefulWidget {
  const TabbedAddTreatmentScreen({
    required this.onCreated,
    super.key,
  });

  final VoidCallback onCreated;

  @override
  State<TabbedAddTreatmentScreen> createState() =>
      _TabbedAddTreatmentScreenState();
}

class _TabbedAddTreatmentScreenState extends State<TabbedAddTreatmentScreen>
    with SingleTickerProviderStateMixin {
  final _medicineFormKey = GlobalKey<FormState>();
  final _scheduleFormKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _strength = TextEditingController();
  final _dose = TextEditingController();
  final _instructions = TextEditingController();

  late final TabController _tabs;
  final List<TimeOfDay> _times = [TimeOfDay.now()];
  final Set<String> _availableTimeZones = {
    'Asia/Tehran',
    'Europe/Berlin',
    'UTC',
  };
  DateTime _startDate = DateTime.now();
  DateTime? _endDate;
  String _timeZone = 'Asia/Tehran';
  String _form = 'tablet';
  String _frequency = 'daily';
  final Set<int> _selectedWeekdays = <int>{
    DateTime.monday,
    DateTime.tuesday,
    DateTime.wednesday,
    DateTime.thursday,
    DateTime.friday,
    DateTime.saturday,
    DateTime.sunday,
  };
  bool _busy = false;
  bool _profileTimeZoneRequested = false;
  String? _error;

  static const _forms = <String, String>{
    'tablet': 'قرص',
    'capsule': 'کپسول',
    'syrup': 'شربت',
    'drop': 'قطره',
    'injection': 'تزریقی',
  };

  static const _weekdayLabels = <int, String>{
    DateTime.saturday: 'ش',
    DateTime.sunday: 'ی',
    DateTime.monday: 'د',
    DateTime.tuesday: 'س',
    DateTime.wednesday: 'چ',
    DateTime.thursday: 'پ',
    DateTime.friday: 'ج',
  };

  static const _backendWeekdays = <int, String>{
    DateTime.monday: 'monday',
    DateTime.tuesday: 'tuesday',
    DateTime.wednesday: 'wednesday',
    DateTime.thursday: 'thursday',
    DateTime.friday: 'friday',
    DateTime.saturday: 'saturday',
    DateTime.sunday: 'sunday',
  };

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _tabs.addListener(() {
      if (mounted && !_tabs.indexIsChanging) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_profileTimeZoneRequested) {
      _profileTimeZoneRequested = true;
      _loadProfileTimeZone();
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    _name.dispose();
    _strength.dispose();
    _dose.dispose();
    _instructions.dispose();
    super.dispose();
  }

  Future<void> _loadProfileTimeZone() async {
    try {
      final currentUser =
          await context.read<LifeMateApiClient>().getCurrentUser();
      final profile = currentUser['profile'] as Map<String, dynamic>?;
      final value = profile?['timeZone']?.toString().trim();
      if (!mounted || value == null || value.isEmpty) return;
      setState(() {
        _availableTimeZones.add(value);
        _timeZone = value;
      });
    } catch (error) {
      debugPrint('WellMate profile timezone was not available: $error');
    }
  }

  Future<void> _pickTime({int? replaceIndex}) async {
    final initialTime = replaceIndex == null
        ? (_times.isEmpty ? TimeOfDay.now() : _times.last)
        : _times[replaceIndex];
    final value =
        await showTimePicker(context: context, initialTime: initialTime);
    if (value == null || !mounted) return;

    var duplicateFound = false;
    for (var index = 0; index < _times.length; index++) {
      final time = _times[index];
      if (index != replaceIndex &&
          time.hour == value.hour &&
          time.minute == value.minute) {
        duplicateFound = true;
        break;
      }
    }
    if (duplicateFound) {
      setState(() => _error = 'این ساعت قبلاً به برنامه اضافه شده است.');
      return;
    }

    setState(() {
      _error = null;
      if (replaceIndex == null) {
        _times.add(value);
      } else {
        _times[replaceIndex] = value;
      }
      _times.sort(
        (left, right) =>
            (left.hour * 60 + left.minute) -
            (right.hour * 60 + right.minute),
      );
    });
  }

  void _removeTime(int index) {
    if (_busy || _times.length <= 1) return;
    setState(() {
      _times.removeAt(index);
      _error = null;
    });
  }

  Future<void> _pickStartDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (value != null && mounted) {
      setState(() {
        _startDate = value;
        if (_endDate != null && _endDate!.isBefore(value)) _endDate = null;
      });
    }
  }

  Future<void> _pickEndDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate.add(const Duration(days: 30)),
      firstDate: _startDate,
      lastDate: _startDate.add(const Duration(days: 3650)),
    );
    if (value != null && mounted) setState(() => _endDate = value);
  }

  bool _validateScheduleSelections() {
    if (_selectedWeekdays.isEmpty) {
      setState(() => _error = 'حداقل یک روز هفته را انتخاب کنید.');
      return false;
    }
    if (_times.isEmpty) {
      setState(() => _error = 'حداقل یک ساعت مصرف را اضافه کنید.');
      return false;
    }
    if (_timeZone.trim().isEmpty) {
      setState(() => _error = 'منطقه زمانی را انتخاب کنید.');
      return false;
    }
    return true;
  }

  void _next() {
    FocusScope.of(context).unfocus();
    if (_tabs.index == 0 && !_medicineFormKey.currentState!.validate()) return;
    if (_tabs.index == 1) {
      if (!_scheduleFormKey.currentState!.validate()) return;
      if (!_validateScheduleSelections()) return;
    }
    setState(() => _error = null);
    _tabs.animateTo((_tabs.index + 1).clamp(0, 2));
  }

  void _previous() {
    FocusScope.of(context).unfocus();
    setState(() => _error = null);
    _tabs.animateTo((_tabs.index - 1).clamp(0, 2));
  }

  Future<void> _create() async {
    if (!_medicineFormKey.currentState!.validate() ||
        !_scheduleFormKey.currentState!.validate()) {
      _tabs.animateTo(_name.text.trim().isEmpty ? 0 : 1);
      return;
    }
    if (!_validateScheduleSelections()) {
      _tabs.animateTo(1);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = context.read<LifeMateApiClient>();
      final medication = await api.createMedication(
        name: _name.text,
        strengthText: _strength.text,
        form: _form,
        notes: _instructions.text,
      );
      final selectedDays = _frequency == 'daily'
          ? _backendWeekdays.keys.toSet()
          : _selectedWeekdays;
      final schedules = buildTreatmentSchedules(
        weekdays: selectedDays,
        times: _times,
        backendWeekdays: _backendWeekdays,
      );
      await api.createTreatmentPlan(
        medicationId: medication['id'].toString(),
        doseText: _dose.text,
        instructions: _instructions.text,
        startDate: _startDate,
        endDate: _endDate,
        timeZone: _timeZone,
        schedules: schedules,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('درمان ثبت شد و برنامه دارویی به‌روزرسانی می‌شود.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      _reset();
      widget.onCreated();
    } on LifeMateApiException catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } catch (error) {
      debugPrint('WellMate treatment creation failed: $error');
      if (mounted) {
        setState(() => _error = 'ثبت درمان انجام نشد. اتصال را بررسی کنید.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _reset() {
    _name.clear();
    _strength.clear();
    _dose.clear();
    _instructions.clear();
    setState(() {
      _times
        ..clear()
        ..add(TimeOfDay.now());
      _startDate = DateTime.now();
      _endDate = null;
      _form = 'tablet';
      _frequency = 'daily';
      _selectedWeekdays
        ..clear()
        ..addAll(_backendWeekdays.keys);
      _error = null;
    });
    _tabs.animateTo(0);
  }

  String get _timesLabel => _times.map(formatTreatmentTime).join('، ');

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'افزودن دارو و برنامه درمان',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: AppColors.darkBlue,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'اطلاعات را در سه مرحله وارد کنید؛ تب‌ها و خلاصه نهایی همیشه در دسترس‌اند.',
                style: TextStyle(color: AppColors.textSecondary, height: 1.5),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.shadowDark.withValues(alpha: 0.45),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: TabBar(
                  controller: _tabs,
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  indicator: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  labelColor: Colors.white,
                  unselectedLabelColor: AppColors.textSecondary,
                  labelStyle: const TextStyle(fontWeight: FontWeight.w800),
                  tabs: const [
                    Tab(text: 'دارو'),
                    Tab(text: 'برنامه'),
                    Tab(text: 'مرور'),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _medicineTab(),
              _scheduleTab(),
              _reviewTab(),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.red.shade100),
              ),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 88),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
              final stackButtons = constraints.maxWidth < 340 || largeText;
              final previousButton = OutlinedButton.icon(
                onPressed: _busy ? null : _previous,
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('مرحله قبل'),
              );
              final primaryButton = FilledButton.icon(
                onPressed:
                    _busy ? null : (_tabs.index == 2 ? _create : _next),
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        _tabs.index == 2
                            ? Icons.add_task_rounded
                            : Icons.arrow_forward_rounded,
                      ),
                label: Text(_tabs.index == 2 ? 'ثبت درمان' : 'مرحله بعد'),
              );

              if (stackButtons) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_tabs.index > 0) ...[
                      previousButton,
                      const SizedBox(height: 8),
                    ],
                    primaryButton,
                  ],
                );
              }
              return Row(
                children: [
                  if (_tabs.index > 0) ...[
                    Expanded(child: previousButton),
                    const SizedBox(width: 10),
                  ],
                  Expanded(flex: 2, child: primaryButton),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _medicineTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Form(
        key: _medicineFormKey,
        child: _SectionCard(
          icon: Icons.medication_rounded,
          title: 'مشخصات دارو',
          subtitle: 'نام، قدرت و شکل دارویی را ثبت کنید.',
          child: Column(
            children: [
              TextFormField(
                controller: _name,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'نام دارو',
                  hintText: 'مثلاً متفورمین',
                  prefixIcon: Icon(Icons.medication_rounded),
                  border: OutlineInputBorder(),
                ),
                validator: (value) => (value?.trim().isNotEmpty ?? false)
                    ? null
                    : 'نام دارو را وارد کنید.',
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _strength,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'قدرت دارو',
                  hintText: 'مثلاً ۵۰۰ میلی‌گرم',
                  prefixIcon: Icon(Icons.science_outlined),
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _form,
                decoration: const InputDecoration(
                  labelText: 'شکل دارویی',
                  prefixIcon: Icon(Icons.category_outlined),
                  border: OutlineInputBorder(),
                ),
                items: _forms.entries
                    .map(
                      (entry) => DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                    )
                    .toList(growable: false),
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _form = value ?? 'tablet'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _scheduleTab() {
    final timeZones = _availableTimeZones.toList()..sort();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Form(
        key: _scheduleFormKey,
        child: Column(
          children: [
            _SectionCard(
              icon: Icons.schedule_rounded,
              title: 'زمان و مقدار مصرف',
              subtitle: 'برای هر نوبت روزانه یک ساعت اضافه کنید.',
              child: Column(
                children: [
                  TextFormField(
                    controller: _dose,
                    decoration: const InputDecoration(
                      labelText: 'مقدار مصرف',
                      hintText: 'مثلاً یک قرص',
                      prefixIcon: Icon(Icons.local_pharmacy_outlined),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) =>
                        (value?.trim().isNotEmpty ?? false)
                            ? null
                            : 'مقدار مصرف را وارد کنید.',
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 14),
                  Column(
                    children: [
                      for (var index = 0; index < _times.length; index++) ...[
                        _DoseTimeTile(
                          key: ValueKey(
                            'treatment-time-${formatTreatmentTime(_times[index])}',
                          ),
                          time: _times[index],
                          canRemove: _times.length > 1 && !_busy,
                          onEdit: _busy
                              ? null
                              : () => _pickTime(replaceIndex: index),
                          onRemove: _busy ? null : () => _removeTime(index),
                        ),
                        if (index != _times.length - 1)
                          const SizedBox(height: 8),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      key: const Key('add-treatment-time'),
                      onPressed: _busy ? null : _pickTime,
                      icon: const Icon(Icons.add_alarm_rounded),
                      label: const Text('افزودن ساعت مصرف'),
                    ),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    key: ValueKey(_timeZone),
                    initialValue: _timeZone,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'منطقه زمانی',
                      prefixIcon: Icon(Icons.public_rounded),
                      border: OutlineInputBorder(),
                    ),
                    items: timeZones
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(
                              value,
                              textDirection: TextDirection.ltr,
                            ),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: _busy
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() => _timeZone = value);
                            }
                          },
                  ),
                  const SizedBox(height: 8),
                  const Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      'یادآورها و دوزها بر اساس این منطقه زمانی ساخته می‌شوند.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.45,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _SectionCard(
              icon: Icons.repeat_rounded,
              title: 'تکرار درمان',
              subtitle: 'هر روز یا روزهای مشخص هفته را انتخاب کنید.',
              child: Column(
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'daily',
                          label: Text('هر روز'),
                          icon: Icon(Icons.calendar_view_week_rounded),
                        ),
                        ButtonSegment(
                          value: 'selected',
                          label: Text('روزهای مشخص'),
                          icon: Icon(Icons.event_available_rounded),
                        ),
                      ],
                      selected: {_frequency},
                      onSelectionChanged: _busy
                          ? null
                          : (values) => setState(() {
                                _frequency = values.first;
                                if (_frequency == 'daily') {
                                  _selectedWeekdays
                                    ..clear()
                                    ..addAll(_backendWeekdays.keys);
                                }
                              }),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: _weekdayLabels.entries.map((entry) {
                      final selected = _selectedWeekdays.contains(entry.key);
                      return FilterChip(
                        selected: selected,
                        label: Text(entry.value),
                        onSelected: _frequency == 'daily' || _busy
                            ? null
                            : (value) => setState(() {
                                  if (value) {
                                    _selectedWeekdays.add(entry.key);
                                  } else {
                                    _selectedWeekdays.remove(entry.key);
                                  }
                                }),
                      );
                    }).toList(growable: false),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _reviewTab() {
    final selectedDays = _frequency == 'daily'
        ? 'هر روز هفته'
        : _weekdayLabels.entries
            .where((entry) => _selectedWeekdays.contains(entry.key))
            .map((entry) => entry.value)
            .join('، ');
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        children: [
          _SectionCard(
            icon: Icons.fact_check_outlined,
            title: 'مرور درمان',
            subtitle: 'پیش از ثبت، جزئیات نهایی را بررسی کنید.',
            child: Column(
              children: [
                _ReviewRow(
                  icon: Icons.medication_rounded,
                  label: 'دارو',
                  value: _name.text.trim().isEmpty
                      ? 'هنوز وارد نشده'
                      : _name.text.trim(),
                ),
                const Divider(height: 28),
                _ReviewRow(
                  icon: Icons.science_outlined,
                  label: 'قدرت و شکل',
                  value:
                      '${_strength.text.trim().isEmpty ? 'بدون قدرت ثبت‌شده' : _strength.text.trim()} • ${_forms[_form]}',
                ),
                const Divider(height: 28),
                _ReviewRow(
                  icon: Icons.schedule_rounded,
                  label: 'دوز و ساعت‌ها',
                  value:
                      '${_dose.text.trim().isEmpty ? 'بدون دوز' : _dose.text.trim()} • ${_timesLabel.isEmpty ? 'بدون ساعت' : _timesLabel}',
                ),
                const Divider(height: 28),
                _ReviewRow(
                  icon: Icons.repeat_rounded,
                  label: 'روزهای مصرف',
                  value: selectedDays.isEmpty ? 'انتخاب نشده' : selectedDays,
                ),
                const Divider(height: 28),
                _ReviewRow(
                  icon: Icons.public_rounded,
                  label: 'منطقه زمانی',
                  value: _timeZone,
                  ltr: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _SectionCard(
            icon: Icons.date_range_rounded,
            title: 'بازه و توضیحات',
            subtitle: 'تاریخ پایان اختیاری است.',
            child: Column(
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _pickStartDate,
                      icon: const Icon(Icons.play_circle_outline_rounded),
                      label: Text('شروع ${_formatDate(_startDate)}'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _pickEndDate,
                      icon: const Icon(Icons.stop_circle_outlined),
                      label: Text(
                        _endDate == null
                            ? 'بدون پایان'
                            : 'پایان ${_formatDate(_endDate!)}',
                      ),
                    ),
                  ],
                ),
                if (_endDate != null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _busy
                          ? null
                          : () => setState(() => _endDate = null),
                      icon: const Icon(Icons.close_rounded),
                      label: const Text('حذف تاریخ پایان'),
                    ),
                  ),
                TextField(
                  controller: _instructions,
                  minLines: 2,
                  maxLines: 4,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'توضیحات و دستور مصرف',
                    hintText: 'مثلاً بعد از غذا',
                    prefixIcon: Icon(Icons.notes_rounded),
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.18),
              ),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.verified_user_outlined, color: AppColors.primary),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'با ثبت این برنامه، دوزهای واقعی در LifeMate ساخته می‌شوند و می‌توانید مصرف یا عدم مصرف را ثبت کنید.',
                    style: TextStyle(height: 1.55),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime value) =>
      '${value.year}/${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')}';

  static String _friendlyError(LifeMateApiException error) {
    switch (error.code) {
      case 'invalid_medication':
      case 'invalid_name':
        return 'مشخصات دارو معتبر نیست.';
      case 'invalid_treatment_plan':
      case 'schedule_required':
      case 'invalid_schedule':
      case 'duplicate_schedule':
        return 'برنامه درمان معتبر نیست.';
      case 'invalid_timeZone':
        return 'منطقه زمانی معتبر نیست.';
      case 'medication_name_conflict':
        return 'دارویی با این نام از قبل وجود دارد.';
      default:
        return error.isUnauthorized
            ? 'نشست شما منقضی شده است؛ دوباره وارد شوید.'
            : 'ثبت درمان انجام نشد. دوباره تلاش کنید.';
    }
  }
}

class _DoseTimeTile extends StatelessWidget {
  const _DoseTimeTile({
    super.key,
    required this.time,
    required this.canRemove,
    required this.onEdit,
    required this.onRemove,
  });

  final TimeOfDay time;
  final bool canRemove;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'ساعت مصرف ${formatTreatmentTime(time)}',
        container: true,
        child: Container(
          padding: const EdgeInsetsDirectional.fromSTEB(14, 8, 6, 8),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.16),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.access_time_rounded, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  formatTreatmentTime(time),
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'ویرایش ساعت',
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                tooltip: canRemove
                    ? 'حذف ساعت'
                    : 'حداقل یک ساعت باید باقی بماند',
                onPressed: canRemove ? onRemove : null,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
        ),
      );
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: AppColors.shadowDark.withValues(alpha: 0.5),
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
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: AppColors.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: AppColors.darkBlue,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            child,
          ],
        ),
      );
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({
    required this.icon,
    required this.label,
    required this.value,
    this.ltr = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool ltr;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  textDirection: ltr ? TextDirection.ltr : null,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ],
      );
}
