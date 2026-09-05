import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';

import '../../core/theme/app_style.dart';
import '../../core/utils/persian_date_utils.dart';
import '../../core/widgets/labeled_form_field.dart';
import 'add_treatment_screen.dart';
import 'offline_treatment_edit.dart';
import 'treatment_schedule_payload.dart';

enum WellMateTreatmentEditSaveState { serverConfirmed, pendingSync }

class EditTreatmentScreen extends StatefulWidget {
  const EditTreatmentScreen({
    super.key,
    required this.plan,
    this.editApi,
    this.offlineEnqueuer,
    this.onSaveStateChanged,
  });

  final Map<String, dynamic> plan;
  final LifeMateEditApi? editApi;
  final WellMateOfflineTreatmentEditEnqueuer? offlineEnqueuer;
  final ValueChanged<WellMateTreatmentEditSaveState>? onSaveStateChanged;

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

  static final _forms = <String, String>{
    'tablet': LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'قرص', en: "Tablet"),
      en: "Tablet",
    ),
    'capsule': LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'کپسول', en: "Capsule"),
      en: "Capsule",
    ),
    'syrup': LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'شربت', en: "Syrup"),
      en: "Syrup",
    ),
    'drop': LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'قطره', en: "Drops"),
      en: "Drops",
    ),
    'injection': LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'تزریقی', en: "Injection"),
      en: "Injection",
    ),
    'other': LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'سایر', en: "Other"),
      en: "Other",
    ),
  };

  static final _weekdayLabels = <int, String>{
    DateTime.saturday: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'ش', en: "Sat"),
      en: "Sat",
    ),
    DateTime.sunday: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'ی', en: "Sun"),
      en: "Sun",
    ),
    DateTime.monday: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'د', en: "Mon"),
      en: "Mon",
    ),
    DateTime.tuesday: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'س', en: "Tue"),
      en: "Tue",
    ),
    DateTime.wednesday: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'چ', en: "Wed"),
      en: "Wed",
    ),
    DateTime.thursday: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'پ', en: "Thu"),
      en: "Thu",
    ),
    DateTime.friday: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'ج', en: "Fri"),
      en: "Fri",
    ),
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
      setState(
        () => _error = LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'این ساعت قبلاً در برنامه وجود دارد.',
            en: "This watch is already in the app.",
          ),
          en: "This watch is already in the app.",
        ),
      );
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
      lastDate: DateTime.now().add(Duration(days: 3650)),
      title: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'تاریخ شروع درمان',
          en: "Treatment start date",
        ),
        en: "Treatment start date",
      ),
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
      initialDate: _endDate ?? _startDate.add(Duration(days: 30)),
      firstDate: _startDate,
      lastDate: _startDate.add(Duration(days: 3650)),
      title: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'تاریخ پایان درمان',
          en: "End date of treatment",
        ),
        en: "End date of treatment",
      ),
    );
    if (value != null && mounted) setState(() => _endDate = value);
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (_busy || !_formKey.currentState!.validate()) return;
    if (_selectedWeekdays.isEmpty) {
      setState(
        () => _error = LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'حداقل یک روز مصرف را انتخاب کنید.',
            en: "Select at least one day of use.",
          ),
          en: "Select at least one day of use.",
        ),
      );
      return;
    }
    if (_times.isEmpty) {
      setState(
        () => _error = LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'حداقل یک ساعت مصرف لازم است.',
            en: "At least one hour of consumption is required.",
          ),
          en: "At least one hour of consumption is required.",
        ),
      );
      return;
    }

    final schedules = buildTreatmentSchedules(
      weekdays: _selectedWeekdays,
      times: _times,
      backendWeekdays: _backendWeekdays,
    );
    final clientRequestId = LifeMateApiClient.createClientRequestId();
    final offlineRequest = WellMateOfflineTreatmentEditRequest(
      clientRequestId: clientRequestId,
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
      schedules: schedules,
      patientReminderMinutesBefore: _patientReminderMinutesBefore,
      caregiverReminderMinutesBefore: _caregiverReminderMinutesBefore,
      status: _status,
    );

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _api.updateTreatmentPlan(
        treatmentPlanId: offlineRequest.treatmentPlanId,
        version: offlineRequest.version,
        medicationVersion: offlineRequest.medicationVersion,
        medicationName: offlineRequest.medicationName,
        strengthText: offlineRequest.strengthText,
        form: offlineRequest.form,
        doseText: offlineRequest.doseText,
        instructions: offlineRequest.instructions,
        startDate: offlineRequest.startDate,
        endDate: offlineRequest.endDate,
        timeZone: offlineRequest.timeZone,
        schedules: offlineRequest.schedules,
        patientReminderMinutesBefore:
            offlineRequest.patientReminderMinutesBefore,
        caregiverReminderMinutesBefore:
            offlineRequest.caregiverReminderMinutesBefore,
        status: offlineRequest.status,
        clientRequestId: clientRequestId,
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
      widget.onSaveStateChanged?.call(
        WellMateTreatmentEditSaveState.serverConfirmed,
      );
      LifeMateNotice.show(
        context,
        type: LifeMateNoticeType.success,
        title: LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'درمان به‌روزرسانی شد',
            en: "Treatment updated",
          ),
          en: "Treatment updated",
        ),
        message: LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'تغییرات درمان با موفقیت ذخیره شد.',
            en: "Treatment changes saved successfully.",
          ),
          en: "Treatment changes saved successfully.",
        ),
      );
      Navigator.of(context).pop(true);
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      if (canQueueTreatmentEditOffline(error)) {
        final queued = await tryQueueTreatmentEditOffline(
          context,
          offlineRequest,
          injectedEnqueuer: widget.offlineEnqueuer,
        );
        if (!mounted) return;
        if (queued) {
          widget.onSaveStateChanged?.call(
            WellMateTreatmentEditSaveState.pendingSync,
          );
          LifeMateNotice.show(
            context,
            type: LifeMateNoticeType.info,
            title: LifeMateRuntimeLocale.select(
              fa: 'تغییرات روی این دستگاه ذخیره شد',
              en: 'Changes saved on this device',
            ),
            message: LifeMateRuntimeLocale.select(
              fa: 'تأیید سرور هنوز انجام نشده است؛ پس از اتصال، همگام‌سازی انجام می‌شود.',
              en: 'Server confirmation is pending; the edit will sync after reconnection.',
            ),
          );
          Navigator.of(context).pop(true);
          return;
        }
      }
      setState(() => _error = _friendlyError(error));
    } catch (error) {
      debugPrint('WellMate treatment update failed: $error');
      if (mounted) {
        setState(
          () => _error = LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'ذخیره تغییرات انجام نشد. اتصال را بررسی کنید.',
              en: "Failed to save changes. Check the connection.",
            ),
            en: "Failed to save changes. Check the connection.",
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reuseFromHistory() async {
    if (_busy) return;
    final draft = TreatmentReuseDraft.fromHistory(widget.plan);
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (routeContext) => Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.background,
            title: Text(
              LifeMateRuntimeLocale.select(
                fa: 'ثبت دوباره درمان',
                en: 'Register treatment again',
              ),
            ),
          ),
          body: TabbedAddTreatmentScreen(
            initialDraft: draft,
            onCreated: () => Navigator.of(routeContext).pop(),
          ),
        ),
      ),
    );
  }

  String _friendlyError(LifeMateApiException error) {
    return switch (error.code) {
      'stale_treatment_plan' ||
      'stale_medication' => LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'این درمان در جای دیگری تغییر کرده است. صفحه را ببندید و دوباره باز کنید.',
          en: "This treatment has been modified elsewhere. Close and reopen the page.",
        ),
        en: "This treatment has been modified elsewhere. Close and reopen the page.",
      ),
      'treatment_plan_not_found' => LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'این درمان دیگر در حساب شما وجود ندارد.',
          en: "This treatment no longer exists in your account.",
        ),
        en: "This treatment no longer exists in your account.",
      ),
      'network_unavailable' ||
      'network_timeout' ||
      'retry_budget_exhausted' => LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'ذخیره آفلاین این تغییر ممکن نشد. اتصال را بررسی و دوباره تلاش کنید.',
          en: "This change could not be saved offline. Check the connection and try again.",
        ),
        en: "This change could not be saved offline. Check the connection and try again.",
      ),
      'session_missing' || 'invalid_session' => LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'نشست شما منقضی شده است. دوباره وارد شوید.',
          en: "Your session has expired. Sign in again.",
        ),
        en: "Your session has expired. Sign in again.",
      ),
      _ => LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'اطلاعات درمان معتبر نیست یا ذخیره انجام نشد.',
          en: "The treatment information is not valid or could not be saved.",
        ),
        en: "The treatment information is not valid or could not be saved.",
      ),
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
        title: Text(
          LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'ویرایش درمان',
              en: "Editing treatment",
            ),
            en: "Editing treatment",
          ),
          style: TextStyle(
            color: AppColors.darkBlue,
            fontWeight: FontWeight.w900,
          ),
        ),
        actions: [
          TextButton.icon(
            key: const ValueKey('reuse-treatment-action'),
            onPressed: _busy ? null : _reuseFromHistory,
            icon: const Icon(Icons.replay_rounded),
            label: Text(
              LifeMateRuntimeLocale.select(fa: 'ثبت دوباره', en: 'Reuse'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Form(
          key: _formKey,
          child: ListView(
            key: ValueKey('edit-treatment-form'),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(20, 12, 20, 36),
            children: [
              _EditSection(
                title: LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'مشخصات درمان',
                    en: "Treatment specifications",
                  ),
                  en: "Treatment specifications",
                ),
                icon: Icons.medication_rounded,
                children: [
                  _textField(
                    controller: _name,
                    label: LifeMateRuntimeLocale.select(
                      fa: LifeMateRuntimeLocale.select(
                        fa: 'نام دارو',
                        en: "name of the drug",
                      ),
                      en: "name of the drug",
                    ),
                    hint: LifeMateRuntimeLocale.select(
                      fa: LifeMateRuntimeLocale.select(
                        fa: 'نام دارو',
                        en: "name of the drug",
                      ),
                      en: "name of the drug",
                    ),
                    icon: Icons.medication_rounded,
                    required: true,
                  ),
                  _textField(
                    controller: _strength,
                    label: LifeMateRuntimeLocale.select(
                      fa: LifeMateRuntimeLocale.select(
                        fa: 'قدرت دارو',
                        en: "The power of medicine",
                      ),
                      en: "The power of medicine",
                    ),
                    hint: LifeMateRuntimeLocale.select(
                      fa: LifeMateRuntimeLocale.select(
                        fa: 'مثلاً ۱۰ میلی‌گرم',
                        en: "For example, 10 mg",
                      ),
                      en: "For example, 10 mg",
                    ),
                    icon: Icons.science_rounded,
                  ),
                  WellMateLabeledField(
                    label: LifeMateRuntimeLocale.select(
                      fa: LifeMateRuntimeLocale.select(
                        fa: 'شکل دارو',
                        en: "Drug form",
                      ),
                      en: "Drug form",
                    ),
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
                    label: LifeMateRuntimeLocale.select(
                      fa: LifeMateRuntimeLocale.select(
                        fa: 'مقدار مصرف',
                        en: "Consumption amount",
                      ),
                      en: "Consumption amount",
                    ),
                    hint: LifeMateRuntimeLocale.select(
                      fa: LifeMateRuntimeLocale.select(
                        fa: 'مثلاً ۱ قرص',
                        en: "For example, 1 tablet",
                      ),
                      en: "For example, 1 tablet",
                    ),
                    icon: Icons.straighten_rounded,
                    required: true,
                  ),
                  WellMateLabeledField(
                    label: LifeMateRuntimeLocale.select(
                      fa: LifeMateRuntimeLocale.select(
                        fa: 'وضعیت درمان',
                        en: "Treatment status",
                      ),
                      en: "Treatment status",
                    ),
                    icon: Icons.toggle_on_rounded,
                    bottomSpacing: 0,
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('edit-treatment-status'),
                      initialValue: _status,
                      decoration: wellMateFieldDecoration(),
                      items: [
                        DropdownMenuItem(
                          value: 'active',
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
                          value: 'stopped',
                          child: Text(
                            LifeMateRuntimeLocale.select(
                              fa: LifeMateRuntimeLocale.select(
                                fa: 'متوقف',
                                en: "stopped",
                              ),
                              en: "stopped",
                            ),
                          ),
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
              SizedBox(height: 16),
              _EditSection(
                title: LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'روزها و ساعت‌های مصرف',
                    en: "Days and hours of use",
                  ),
                  en: "Days and hours of use",
                ),
                icon: Icons.schedule_rounded,
                children: [
                  Text(
                    LifeMateRuntimeLocale.select(
                      fa: LifeMateRuntimeLocale.select(
                        fa: 'روزهای مصرف',
                        en: "days of use",
                      ),
                      en: "days of use",
                    ),
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  SizedBox(height: 10),
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
                  SizedBox(height: 18),
                  Text(
                    LifeMateRuntimeLocale.select(
                      fa: LifeMateRuntimeLocale.select(
                        fa: 'ساعت‌های مصرف',
                        en: "Hours of use",
                      ),
                      en: "Hours of use",
                    ),
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var index = 0; index < _times.length; index++)
                        InputChip(
                          label: Text(formatAppTime(context, _times[index])),
                          avatar: Icon(Icons.access_time_rounded, size: 18),
                          onPressed: _busy
                              ? null
                              : () => _pickTime(replaceIndex: index),
                          onDeleted: _busy || _times.length == 1
                              ? null
                              : () => setState(() => _times.removeAt(index)),
                        ),
                      ActionChip(
                        avatar: Icon(Icons.add_rounded, size: 18),
                        label: Text(
                          LifeMateRuntimeLocale.select(
                            fa: LifeMateRuntimeLocale.select(
                              fa: 'افزودن ساعت',
                              en: "Add hours",
                            ),
                            en: "Add hours",
                          ),
                        ),
                        onPressed: _busy ? null : _pickTime,
                      ),
                    ],
                  ),
                ],
              ),
              SizedBox(height: 16),
              _EditSection(
                title: LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'بازه و یادآوری',
                    en: "interval and reminder",
                  ),
                  en: "interval and reminder",
                ),
                icon: Icons.notifications_active_rounded,
                children: [
                  _DateField(
                    label: LifeMateRuntimeLocale.select(
                      fa: LifeMateRuntimeLocale.select(
                        fa: 'تاریخ شروع',
                        en: "start date",
                      ),
                      en: "start date",
                    ),
                    icon: Icons.calendar_today_rounded,
                    value: formatAppDate(context, _startDate),
                    onTap: _busy ? null : _pickStartDate,
                  ),
                  _DateField(
                    label: LifeMateRuntimeLocale.select(
                      fa: LifeMateRuntimeLocale.select(
                        fa: 'تاریخ پایان',
                        en: "end date",
                      ),
                      en: "end date",
                    ),
                    icon: Icons.event_available_rounded,
                    value: _endDate == null
                        ? LifeMateRuntimeLocale.select(
                            fa: LifeMateRuntimeLocale.select(
                              fa: 'بدون تاریخ پایان',
                              en: "No end date",
                            ),
                            en: "No end date",
                          )
                        : formatAppDate(context, _endDate!),
                    onTap: _busy ? null : _pickEndDate,
                    suffix: _endDate == null
                        ? null
                        : IconButton(
                            tooltip: LifeMateRuntimeLocale.select(
                              fa: LifeMateRuntimeLocale.select(
                                fa: 'حذف تاریخ پایان',
                                en: "Remove the end date",
                              ),
                              en: "Remove the end date",
                            ),
                            onPressed: _busy
                                ? null
                                : () => setState(() => _endDate = null),
                            icon: Icon(Icons.close_rounded),
                          ),
                  ),
                  WellMateLabeledField(
                    label: LifeMateRuntimeLocale.select(
                      fa: LifeMateRuntimeLocale.select(
                        fa: 'یادآوری برای خودم',
                        en: "A reminder to myself",
                      ),
                      en: "A reminder to myself",
                    ),
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
                    label: LifeMateRuntimeLocale.select(
                      fa: LifeMateRuntimeLocale.select(
                        fa: 'یادآوری برای مراقب',
                        en: "Reminder for caregivers",
                      ),
                      en: "Reminder for caregivers",
                    ),
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
                    label: LifeMateRuntimeLocale.select(
                      fa: LifeMateRuntimeLocale.select(
                        fa: 'منطقه زمانی',
                        en: "time zone",
                      ),
                      en: "time zone",
                    ),
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
              SizedBox(height: 16),
              _EditSection(
                title: LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'توضیحات',
                    en: "Description",
                  ),
                  en: "Description",
                ),
                icon: Icons.notes_rounded,
                children: [
                  WellMateLabeledField(
                    label: LifeMateRuntimeLocale.select(
                      fa: LifeMateRuntimeLocale.select(
                        fa: 'دستور مصرف یا یادداشت',
                        en: "Instructions for use or notes",
                      ),
                      en: "Instructions for use or notes",
                    ),
                    icon: Icons.edit_note_rounded,
                    bottomSpacing: 0,
                    child: TextFormField(
                      controller: _instructions,
                      minLines: 3,
                      maxLines: 6,
                      decoration: wellMateFieldDecoration(
                        hint: LifeMateRuntimeLocale.select(
                          fa: LifeMateRuntimeLocale.select(
                            fa: 'مثلاً بعد از غذا',
                            en: "For example, after a meal",
                          ),
                          en: "For example, after a meal",
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (_error != null) ...[
                SizedBox(height: 14),
                Container(
                  padding: EdgeInsets.all(14),
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
              SizedBox(height: 20),
              FilledButton.icon(
                key: ValueKey('save-treatment-edit'),
                style: FilledButton.styleFrom(
                  minimumSize: Size.fromHeight(56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                onPressed: _busy ? null : _save,
                icon: _busy
                    ? SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(Icons.save_rounded),
                label: Text(
                  _busy
                      ? LifeMateRuntimeLocale.select(
                          fa: LifeMateRuntimeLocale.select(
                            fa: 'در حال ذخیره...',
                            en: "Saving...",
                          ),
                          en: "Saving...",
                        )
                      : LifeMateRuntimeLocale.select(
                          fa: LifeMateRuntimeLocale.select(
                            fa: 'ذخیره تغییرات درمان',
                            en: "Save treatment changes",
                          ),
                          en: "Save treatment changes",
                        ),
                  style: TextStyle(fontWeight: FontWeight.w900),
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
                  ? LifeMateRuntimeLocale.select(
                      fa: LifeMateRuntimeLocale.select(
                        fa: '$label را وارد کنید.',
                        en: "Enter $label.",
                      ),
                      en: "Enter $label.",
                    )
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
