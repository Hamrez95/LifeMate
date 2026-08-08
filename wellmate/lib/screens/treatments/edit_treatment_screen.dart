import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';

import '../../core/theme/app_style.dart';
import '../../core/utils/persian_date_utils.dart';
import '../../core/widgets/labeled_form_field.dart';
import 'treatment_schedule_payload.dart';

class EditTreatmentScreen extends StatefulWidget {
  const EditTreatmentScreen({super.key, required this.plan, this.editApi});

  final Map<String, dynamic> plan;
  final LifeMateEditApi? editApi;

  @override
  State<EditTreatmentScreen> createState() => _EditTreatmentScreenState();
}

class _EditTreatmentScreenState extends State<EditTreatmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _strength = TextEditingController();
  final _dose = TextEditingController();
  final _instructions = TextEditingController();

  final List<TimeOfDay> _times = <TimeOfDay>[];
  final Set<int> _selectedWeekdays = <int>{};
  final Set<String> _availableTimeZones = <String>{
    'Asia/Tehran',
    'Europe/Berlin',
    'UTC',
  };

  late DateTime _startDate;
  DateTime? _endDate;
  late String _timeZone;
  late String _form;
  late String _status;
  late int _patientReminderMinutesBefore;
  late int _caregiverReminderMinutesBefore;
  late int _version;
  late int _medicationVersion;

  bool _busy = false;
  String? _error;

  static const _forms = <String, String>{
    'tablet': 'قرص',
    'capsule': 'کپسول',
    'syrup': 'شربت',
    'drop': 'قطره',
    'injection': 'تزریقی',
    'other': 'سایر',
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

  static final _weekdayByBackend = <String, int>{
    for (final entry in _backendWeekdays.entries) entry.value: entry.key,
  };

  LifeMateEditApi get _api =>
      widget.editApi ?? LifeMateEditApi.fromEnvironment();

  @override
  void initState() {
    super.initState();
    _hydrate(widget.plan);
  }

  void _hydrate(Map<String, dynamic> plan) {
    final medication = plan['medication'] is Map<String, dynamic>
        ? Map<String, dynamic>.from(plan['medication'] as Map)
        : <String, dynamic>{};
    _name.text = medication['name']?.toString() ?? '';
    _strength.text = medication['strengthText']?.toString() ?? '';
    _dose.text = plan['doseText']?.toString() ?? '';
    _instructions.text = plan['instructions']?.toString() ?? '';
    _form = medication['form']?.toString().trim().isNotEmpty == true
        ? medication['form'].toString()
        : 'tablet';
    if (!_forms.containsKey(_form)) _form = 'other';
    _status = plan['status']?.toString().toLowerCase() == 'active'
        ? 'active'
        : 'stopped';
    _startDate =
        DateTime.tryParse(plan['startDate']?.toString() ?? '') ??
        DateTime.now();
    _endDate = DateTime.tryParse(plan['endDate']?.toString() ?? '');
    _timeZone = plan['timeZone']?.toString().trim().isNotEmpty == true
        ? plan['timeZone'].toString()
        : 'Asia/Tehran';
    _availableTimeZones.add(_timeZone);
    _patientReminderMinutesBefore = LifeMateReminderLeadTimes.normalize(
      plan['patientReminderMinutesBefore'],
      fallback: LifeMateReminderLeadTimes.defaultPatientMinutes,
    );
    _caregiverReminderMinutesBefore = LifeMateReminderLeadTimes.normalize(
      plan['caregiverReminderMinutesBefore'],
      fallback: LifeMateReminderLeadTimes.defaultCaregiverMinutes,
    );
    _version = int.tryParse(plan['version']?.toString() ?? '') ?? 1;
    _medicationVersion =
        int.tryParse(medication['version']?.toString() ?? '') ?? 1;

    final schedules = plan['schedules'] is List
        ? plan['schedules'] as List
        : const [];
    for (final raw in schedules) {
      if (raw is! Map) continue;
      final schedule = Map<String, dynamic>.from(raw);
      final day =
          _weekdayByBackend[schedule['dayOfWeek']?.toString().toLowerCase()];
      if (day != null) _selectedWeekdays.add(day);
      final parsedTime = _parseTime(schedule['localTime']);
      if (parsedTime != null &&
          !_times.any(
            (value) =>
                value.hour == parsedTime.hour &&
                value.minute == parsedTime.minute,
          )) {
        _times.add(parsedTime);
      }
    }
    if (_selectedWeekdays.isEmpty) {
      _selectedWeekdays.addAll(_backendWeekdays.keys);
    }
    if (_times.isEmpty) _times.add(TimeOfDay.now());
    _sortTimes();
  }

  @override
  void dispose() {
    _name.dispose();
    _strength.dispose();
    _dose.dispose();
    _instructions.dispose();
    super.dispose();
  }

  TimeOfDay? _parseTime(dynamic value) {
    final parts = value?.toString().split(':') ?? const [];
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null || hour > 23 || minute > 59) {
      return null;
    }
    return TimeOfDay(hour: hour, minute: minute);
  }

  void _sortTimes() {
    _times.sort(
      (left, right) =>
          (left.hour * 60 + left.minute) - (right.hour * 60 + right.minute),
    );
  }

  Future<void> _pickTime({int? replaceIndex}) async {
    final initial = replaceIndex == null ? _times.last : _times[replaceIndex];
    final value = await showTimePicker(context: context, initialTime: initial);
    if (value == null || !mounted) return;
    final duplicate = _times.asMap().entries.any(
      (entry) =>
          entry.key != replaceIndex &&
          entry.value.hour == value.hour &&
          entry.value.minute == value.minute,
    );
    if (duplicate) {
      setState(() => _error = 'این ساعت قبلاً در برنامه وجود دارد.');
      return;
    }
    setState(() {
      _error = null;
      if (replaceIndex == null) {
        _times.add(value);
      } else {
        _times[replaceIndex] = value;
      }
      _sortTimes();
    });
  }

  Future<void> _pickStartDate() async {
    final value = await showAppDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      title: 'تاریخ شروع درمان',
    );
    if (value == null || !mounted) return;
    setState(() {
      _startDate = value;
      if (_endDate != null && _endDate!.isBefore(value)) _endDate = null;
    });
  }

  Future<void> _pickEndDate() async {
    final value = await showAppDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate.add(const Duration(days: 30)),
      firstDate: _startDate,
      lastDate: _startDate.add(const Duration(days: 3650)),
      title: 'تاریخ پایان درمان',
    );
    if (value != null && mounted) setState(() => _endDate = value);
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (_busy || !_formKey.currentState!.validate()) return;
    if (_selectedWeekdays.isEmpty) {
      setState(() => _error = 'حداقل یک روز مصرف را انتخاب کنید.');
      return;
    }
    if (_times.isEmpty) {
      setState(() => _error = 'حداقل یک ساعت مصرف لازم است.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _api.updateTreatmentPlan(
        treatmentPlanId: widget.plan['id'].toString(),
        version: _version,
        medicationVersion: _medicationVersion,
        medicationName: _name.text,
        strengthText: _strength.text,
        form: _form,
        doseText: _dose.text,
        instructions: _instructions.text,
        startDate: _startDate,
        endDate: _endDate,
        timeZone: _timeZone,
        schedules: buildTreatmentSchedules(
          weekdays: _selectedWeekdays,
          times: _times,
          backendWeekdays: _backendWeekdays,
        ),
        patientReminderMinutesBefore: _patientReminderMinutesBefore,
        caregiverReminderMinutesBefore: _caregiverReminderMinutesBefore,
        status: _status,
      );
      _version =
          int.tryParse(result['version']?.toString() ?? '') ?? _version + 1;
      final medication = result['medication'];
      if (medication is Map) {
        _medicationVersion =
            int.tryParse(medication['version']?.toString() ?? '') ??
            _medicationVersion + 1;
      }
      if (!mounted) return;
      LifeMateNotice.show(
        context,
        type: LifeMateNoticeType.success,
        title: 'درمان به‌روزرسانی شد',
        message: 'تغییرات درمان با موفقیت ذخیره شد.',
      );
      Navigator.of(context).pop(true);
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(error));
    } catch (error) {
      debugPrint('WellMate treatment update failed: $error');
      if (mounted) {
        setState(
          () => _error = 'ذخیره تغییرات انجام نشد. اتصال را بررسی کنید.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendlyError(LifeMateApiException error) {
    return switch (error.code) {
      'stale_treatment_plan' || 'stale_medication' =>
        'این درمان در جای دیگری تغییر کرده است. صفحه را ببندید و دوباره باز کنید.',
      'treatment_plan_not_found' => 'این درمان دیگر در حساب شما وجود ندارد.',
      'network_unavailable' =>
        'اتصال اینترنت برای ذخیره تغییرات در دسترس نیست.',
      'session_missing' ||
      'invalid_session' => 'نشست شما منقضی شده است. دوباره وارد شوید.',
      _ => 'اطلاعات درمان معتبر نیست یا ذخیره انجام نشد.',
    };
  }

  @override
  Widget build(BuildContext context) {
    final zones = _availableTimeZones.toList()..sort();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text(
          'ویرایش درمان',
          style: TextStyle(
            color: AppColors.darkBlue,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Form(
          key: _formKey,
          child: ListView(
            key: const ValueKey('edit-treatment-form'),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
            children: [
              _EditSection(
                title: 'مشخصات درمان',
                icon: Icons.medication_rounded,
                children: [
                  _textField(
                    controller: _name,
                    label: 'نام دارو',
                    hint: 'نام دارو',
                    icon: Icons.medication_rounded,
                    required: true,
                  ),
                  _textField(
                    controller: _strength,
                    label: 'قدرت دارو',
                    hint: 'مثلاً ۱۰ میلی‌گرم',
                    icon: Icons.science_rounded,
                  ),
                  WellMateLabeledField(
                    label: 'شکل دارو',
                    icon: Icons.category_rounded,
                    child: DropdownButtonFormField<String>(
                      initialValue: _form,
                      isExpanded: true,
                      decoration: wellMateFieldDecoration(),
                      items: [
                        for (final entry in _forms.entries)
                          DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                      ],
                      onChanged: _busy
                          ? null
                          : (value) => setState(() => _form = value ?? _form),
                    ),
                  ),
                  _textField(
                    controller: _dose,
                    label: 'مقدار مصرف',
                    hint: 'مثلاً ۱ قرص',
                    icon: Icons.straighten_rounded,
                    required: true,
                  ),
                  WellMateLabeledField(
                    label: 'وضعیت درمان',
                    icon: Icons.toggle_on_rounded,
                    bottomSpacing: 0,
                    child: DropdownButtonFormField<String>(
                      key: const ValueKey('edit-treatment-status'),
                      initialValue: _status,
                      decoration: wellMateFieldDecoration(),
                      items: const [
                        DropdownMenuItem(value: 'active', child: Text('فعال')),
                        DropdownMenuItem(
                          value: 'stopped',
                          child: Text('متوقف'),
                        ),
                      ],
                      onChanged: _busy
                          ? null
                          : (value) =>
                                setState(() => _status = value ?? _status),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _EditSection(
                title: 'روزها و ساعت‌های مصرف',
                icon: Icons.schedule_rounded,
                children: [
                  const Text(
                    'روزهای مصرف',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final entry in _weekdayLabels.entries)
                        FilterChip(
                          label: Text(entry.value),
                          selected: _selectedWeekdays.contains(entry.key),
                          onSelected: _busy
                              ? null
                              : (selected) => setState(() {
                                  if (selected) {
                                    _selectedWeekdays.add(entry.key);
                                  } else {
                                    _selectedWeekdays.remove(entry.key);
                                  }
                                }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'ساعت‌های مصرف',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var index = 0; index < _times.length; index++)
                        InputChip(
                          label: Text(formatAppTime(context, _times[index])),
                          avatar: const Icon(
                            Icons.access_time_rounded,
                            size: 18,
                          ),
                          onPressed: _busy
                              ? null
                              : () => _pickTime(replaceIndex: index),
                          onDeleted: _busy || _times.length == 1
                              ? null
                              : () => setState(() => _times.removeAt(index)),
                        ),
                      ActionChip(
                        avatar: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('افزودن ساعت'),
                        onPressed: _busy ? null : _pickTime,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _EditSection(
                title: 'بازه و یادآوری',
                icon: Icons.notifications_active_rounded,
                children: [
                  _DateField(
                    label: 'تاریخ شروع',
                    icon: Icons.calendar_today_rounded,
                    value: formatAppDate(context, _startDate),
                    onTap: _busy ? null : _pickStartDate,
                  ),
                  _DateField(
                    label: 'تاریخ پایان',
                    icon: Icons.event_available_rounded,
                    value: _endDate == null
                        ? 'بدون تاریخ پایان'
                        : formatAppDate(context, _endDate!),
                    onTap: _busy ? null : _pickEndDate,
                    suffix: _endDate == null
                        ? null
                        : IconButton(
                            tooltip: 'حذف تاریخ پایان',
                            onPressed: _busy
                                ? null
                                : () => setState(() => _endDate = null),
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                  WellMateLabeledField(
                    label: 'یادآوری برای خودم',
                    icon: Icons.notifications_active_rounded,
                    child: DropdownButtonFormField<int>(
                      initialValue: _patientReminderMinutesBefore,
                      isExpanded: true,
                      decoration: wellMateFieldDecoration(),
                      items: [
                        for (final value in LifeMateReminderLeadTimes.presets)
                          DropdownMenuItem(
                            value: value,
                            child: Text(LifeMateReminderLeadTimes.label(value)),
                          ),
                      ],
                      onChanged: _busy
                          ? null
                          : (value) => setState(() {
                              _patientReminderMinutesBefore =
                                  value ?? _patientReminderMinutesBefore;
                            }),
                    ),
                  ),
                  WellMateLabeledField(
                    label: 'یادآوری برای مراقب',
                    icon: Icons.family_restroom_rounded,
                    child: DropdownButtonFormField<int>(
                      initialValue: _caregiverReminderMinutesBefore,
                      isExpanded: true,
                      decoration: wellMateFieldDecoration(),
                      items: [
                        for (final value in LifeMateReminderLeadTimes.presets)
                          DropdownMenuItem(
                            value: value,
                            child: Text(LifeMateReminderLeadTimes.label(value)),
                          ),
                      ],
                      onChanged: _busy
                          ? null
                          : (value) => setState(() {
                              _caregiverReminderMinutesBefore =
                                  value ?? _caregiverReminderMinutesBefore;
                            }),
                    ),
                  ),
                  WellMateLabeledField(
                    label: 'منطقه زمانی',
                    icon: Icons.public_rounded,
                    bottomSpacing: 0,
                    child: DropdownButtonFormField<String>(
                      initialValue: _timeZone,
                      isExpanded: true,
                      decoration: wellMateFieldDecoration(),
                      items: [
                        for (final zone in zones)
                          DropdownMenuItem(value: zone, child: Text(zone)),
                      ],
                      onChanged: _busy
                          ? null
                          : (value) =>
                                setState(() => _timeZone = value ?? _timeZone),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _EditSection(
                title: 'توضیحات',
                icon: Icons.notes_rounded,
                children: [
                  WellMateLabeledField(
                    label: 'دستور مصرف یا یادداشت',
                    icon: Icons.edit_note_rounded,
                    bottomSpacing: 0,
                    child: TextFormField(
                      controller: _instructions,
                      minLines: 3,
                      maxLines: 6,
                      decoration: wellMateFieldDecoration(
                        hint: 'مثلاً بعد از غذا',
                      ),
                    ),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.red.shade100),
                  ),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton.icon(
                key: const ValueKey('save-treatment-edit'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                onPressed: _busy ? null : _save,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_rounded),
                label: Text(
                  _busy ? 'در حال ذخیره...' : 'ذخیره تغییرات درمان',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool required = false,
  }) {
    return WellMateLabeledField(
      label: label,
      icon: icon,
      required: required,
      child: TextFormField(
        controller: controller,
        enabled: !_busy,
        decoration: wellMateFieldDecoration(hint: hint),
        validator: required
            ? (value) => value == null || value.trim().isEmpty
                  ? '$label را وارد کنید.'
                  : null
            : null,
      ),
    );
  }
}

class _EditSection extends StatelessWidget {
  const _EditSection({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowDark.withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: AppColors.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: AppColors.darkBlue,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ...children,
        ],
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.icon,
    required this.value,
    required this.onTap,
    this.suffix,
  });

  final String label;
  final IconData icon;
  final String value;
  final VoidCallback? onTap;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    return WellMateLabeledField(
      label: label,
      icon: icon,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: InputDecorator(
          decoration: wellMateFieldDecoration(suffixIcon: suffix),
          child: Text(
            value,
            style: const TextStyle(
              color: AppColors.darkBlue,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}
