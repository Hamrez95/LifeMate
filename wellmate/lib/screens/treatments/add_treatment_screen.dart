import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_style.dart';
import '../../core/utils/persian_date_utils.dart';
import '../../core/widgets/labeled_form_field.dart';
import 'offline_treatment_create.dart';
import 'treatment_recurrence_editor.dart';
import 'treatment_schedule_payload.dart';

/// Kept under the historical class name so existing routes remain compatible.
/// The form is intentionally a single scrollable page; there is no internal
/// timeline or three-step navigation anymore.
class TabbedAddTreatmentScreen extends StatefulWidget {
  const TabbedAddTreatmentScreen({
    required this.onCreated,
    super.key,
    this.initialDraft,
  });

  final VoidCallback onCreated;
  final TreatmentReuseDraft? initialDraft;

  @override
  State<TabbedAddTreatmentScreen> createState() =>
      _TabbedAddTreatmentScreenState();
}

class _TabbedAddTreatmentScreenState extends State<TabbedAddTreatmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _strength = TextEditingController();
  final _dose = TextEditingController();
  final _instructions = TextEditingController();

  final List<TimeOfDay> _times = <TimeOfDay>[TimeOfDay.now()];
  final Set<String> _availableTimeZones = <String>{
    'Asia/Tehran',
    'Europe/Berlin',
    'UTC',
  };
  final Set<int> _selectedWeekdays = <int>{
    DateTime.monday,
    DateTime.tuesday,
    DateTime.wednesday,
    DateTime.thursday,
    DateTime.friday,
    DateTime.saturday,
    DateTime.sunday,
  };

  DateTime _startDate = DateTime.now();
  DateTime? _endDate;
  String _timeZone = 'Asia/Tehran';
  String _form = 'tablet';
  String _frequency = 'daily';
  TreatmentRecurrenceSelection _recurrenceSelection =
      const TreatmentRecurrenceSelection.explicit();
  int _scheduleEditorVersion = 0;
  int _patientReminderMinutesBefore =
      LifeMateReminderLeadTimes.defaultPatientMinutes;
  int _caregiverReminderMinutesBefore =
      LifeMateReminderLeadTimes.defaultCaregiverMinutes;
  bool _busy = false;
  bool _profileTimeZoneRequested = false;
  String? _error;
  List<LifeMateHistoryUsage> _medicationHistory = const [];
  bool _historyLoading = false;

  static final _forms = <String, String>{
    'tablet': LifeMateRuntimeLocale.select(fa: 'قرص', en: 'Tablet'),
    'capsule': LifeMateRuntimeLocale.select(fa: 'کپسول', en: 'Capsule'),
    'syrup': LifeMateRuntimeLocale.select(fa: 'شربت', en: 'Syrup'),
    'drop': LifeMateRuntimeLocale.select(fa: 'قطره', en: 'Drops'),
    'injection': LifeMateRuntimeLocale.select(fa: 'تزریقی', en: 'Injection'),
  };

  static final _weekdayLabels = <int, String>{
    DateTime.saturday: LifeMateRuntimeLocale.select(fa: 'ش', en: 'Sat'),
    DateTime.sunday: LifeMateRuntimeLocale.select(fa: 'ی', en: 'Sun'),
    DateTime.monday: LifeMateRuntimeLocale.select(fa: 'د', en: 'Mon'),
    DateTime.tuesday: LifeMateRuntimeLocale.select(fa: 'س', en: 'Tue'),
    DateTime.wednesday: LifeMateRuntimeLocale.select(fa: 'چ', en: 'Wed'),
    DateTime.thursday: LifeMateRuntimeLocale.select(fa: 'پ', en: 'Thu'),
    DateTime.friday: LifeMateRuntimeLocale.select(fa: 'ج', en: 'Fri'),
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
    _applyInitialDraft(widget.initialDraft);
    if (widget.initialDraft != null) _profileTimeZoneRequested = true;
    _name.addListener(_onMedicationQueryChanged);
    _loadMedicationHistory();
  }

  void _applyInitialDraft(TreatmentReuseDraft? draft) {
    if (draft == null) return;
    _name.text = draft.medicationName;
    _strength.text = draft.strengthText ?? '';
    _dose.text = draft.doseText;
    _instructions.text = draft.instructions ?? '';
    if (_forms.containsKey(draft.form)) _form = draft.form;
    _timeZone = draft.timeZone;
    _availableTimeZones.add(draft.timeZone);
    _patientReminderMinutesBefore = draft.patientReminderMinutesBefore;
    _caregiverReminderMinutesBefore = draft.caregiverReminderMinutesBefore;
    final byName = <String, int>{
      for (final entry in _backendWeekdays.entries) entry.value: entry.key,
    };
    final days = <int>{};
    final times = <TimeOfDay>[];
    for (final schedule in draft.schedules) {
      final day = byName[schedule['dayOfWeek']];
      if (day != null) days.add(day);
      final parts = (schedule['localTime'] ?? '').split(':');
      if (parts.length < 2) continue;
      final hour = int.tryParse(parts[0]);
      final minute = int.tryParse(parts[1]);
      if (hour == null || minute == null || hour > 23 || minute > 59) continue;
      final value = TimeOfDay(hour: hour, minute: minute);
      if (!times.any(
        (item) => item.hour == value.hour && item.minute == value.minute,
      )) {
        times.add(value);
      }
    }
    if (days.isNotEmpty) {
      _selectedWeekdays
        ..clear()
        ..addAll(days);
      _frequency = days.length == 7 ? 'daily' : 'weekly';
    }
    if (times.isNotEmpty) {
      _times
        ..clear()
        ..addAll(times);
    }
  }

  void _onMedicationQueryChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadMedicationHistory() async {
    if (_historyLoading) return;
    setState(() => _historyLoading = true);
    try {
      final plans = await context.read<LifeMateApiClient>().getTreatmentPlans();
      final values = <LifeMateHistoryUsage>[];
      for (final plan in plans) {
        final medication = plan['medication'];
        if (medication is! Map) continue;
        final name = medication['name']?.toString().trim() ?? '';
        if (name.isEmpty) continue;
        values.add(
          LifeMateHistoryUsage(
            kind: LifeMateHistorySuggestionKind.medication,
            value: name,
            usedAt: DateTime.tryParse(plan['updatedAtUtc']?.toString() ?? '') ??
                DateTime.tryParse(plan['startDate']?.toString() ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0),
            context: plan['doseText']?.toString(),
          ),
        );
      }
      if (mounted) setState(() => _medicationHistory = List.unmodifiable(values));
    } catch (error) {
      debugPrint('WellMate medication history unavailable: $error');
    } finally {
      if (mounted) setState(() => _historyLoading = false);
    }
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
    _name.removeListener(_onMedicationQueryChanged);
    _name.dispose();
    _strength.dispose();
    _dose.dispose();
    _instructions.dispose();
    super.dispose();
  }

  Future<void> _loadProfileTimeZone() async {
    try {
      final currentUser = await context
          .read<LifeMateApiClient>()
          .getCurrentUser();
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
    final initial = replaceIndex == null
        ? (_times.isEmpty ? TimeOfDay.now() : _times.last)
        : _times[replaceIndex];
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
          fa: 'این ساعت قبلاً به برنامه اضافه شده است.',
          en: 'This time is already in the schedule.',
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
      _times.sort(
        (left, right) =>
            (left.hour * 60 + left.minute) - (right.hour * 60 + right.minute),
      );
    });
  }

  Future<void> _pickStartDate() async {
    final value = await showAppDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      title: LifeMateRuntimeLocale.select(
        fa: 'تاریخ شروع درمان',
        en: 'Treatment start date',
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
      initialDate: _endDate ?? _startDate.add(const Duration(days: 30)),
      firstDate: _startDate,
      lastDate: _startDate.add(const Duration(days: 3650)),
      title: LifeMateRuntimeLocale.select(
        fa: 'تاریخ پایان درمان',
        en: 'Treatment end date',
      ),
    );
    if (value != null && mounted) setState(() => _endDate = value);
  }

  bool _validateScheduleSelections() {
    if (_recurrenceSelection.enabled) {
      if (_recurrenceSelection.anchor == null) {
        setState(
          () => _error = LifeMateRuntimeLocale.select(
            fa: 'ساعت شروع اولین نوبت را انتخاب کنید.',
            en: 'Select the first occurrence time.',
          ),
        );
        return false;
      }
      return true;
    }
    if (_selectedWeekdays.isEmpty) {
      setState(
        () => _error = LifeMateRuntimeLocale.select(
          fa: 'حداقل یک روز هفته را انتخاب کنید.',
          en: 'Select at least one day of the week.',
        ),
      );
      return false;
    }
    if (_times.isEmpty) {
      setState(
        () => _error = LifeMateRuntimeLocale.select(
          fa: 'حداقل یک ساعت مصرف را اضافه کنید.',
          en: 'Add at least one administration time.',
        ),
      );
      return false;
    }
    return true;
  }

  Future<void> _create() async {
    FocusScope.of(context).unfocus();
    if (_busy || !_formKey.currentState!.validate()) return;
    if (!_validateScheduleSelections()) return;

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
      final schedules = _recurrenceSelection.enabled
          ? <Map<String, String>>[]
          : buildTreatmentSchedules(
              weekdays: selectedDays,
              times: _times,
              backendWeekdays: _backendWeekdays,
            );
      final clientRequestId = LifeMateApiClient.createClientRequestId();
      final offlineRequest = WellMateOfflineTreatmentCreateRequest(
        clientRequestId: clientRequestId,
        medicationId: medication['id'].toString(),
        doseText: _dose.text,
        instructions: _instructions.text,
        startDate: _startDate,
        endDate: _endDate,
        timeZone: _timeZone,
        schedules: schedules,
        patientReminderMinutesBefore: _patientReminderMinutesBefore,
        caregiverReminderMinutesBefore: _caregiverReminderMinutesBefore,
      );
      var pendingSync = false;
      try {
        await api.createTreatmentPlan(
          medicationId: offlineRequest.medicationId,
          doseText: offlineRequest.doseText,
          instructions: offlineRequest.instructions,
          startDate: offlineRequest.startDate,
          endDate: offlineRequest.endDate,
          timeZone: offlineRequest.timeZone,
          schedules: offlineRequest.schedules,
          recurrence: _recurrenceSelection.rule(endDate: _endDate),
          recurrenceStartLocalTime: _recurrenceSelection.anchorLocalTime,
          patientReminderMinutesBefore:
              offlineRequest.patientReminderMinutesBefore,
          caregiverReminderMinutesBefore:
              offlineRequest.caregiverReminderMinutesBefore,
          clientRequestId: clientRequestId,
        );
      } on LifeMateApiException catch (error) {
        if (_recurrenceSelection.enabled ||
            !canQueueTreatmentCreateOffline(error)) {
          rethrow;
        }
        final queued = await tryQueueTreatmentCreateOffline(
          context,
          offlineRequest,
        );
        if (!queued) rethrow;
        pendingSync = true;
      }
      if (!mounted) return;
      LifeMateNotice.show(
        context,
        type: pendingSync ? LifeMateNoticeType.info : LifeMateNoticeType.success,
        title: LifeMateRuntimeLocale.select(
          fa: pendingSync ? 'درمان روی این دستگاه ذخیره شد' : 'درمان ثبت شد',
          en: pendingSync
              ? 'Treatment saved on this device'
              : 'Treatment was recorded',
        ),
        message: LifeMateRuntimeLocale.select(
          fa: pendingSync
              ? 'تأیید سرور هنوز انجام نشده است؛ پس از اتصال، برنامه درمان همگام‌سازی می‌شود.'
              : 'برنامه درمان ذخیره شد و نوبت‌های آینده به‌صورت خودکار ساخته می‌شوند.',
          en: pendingSync
              ? 'Server confirmation is pending; the treatment plan will sync after reconnection.'
              : 'The treatment plan was saved and future occurrences will be generated automatically.',
        ),
      );
      _reset();
      widget.onCreated();
    } on LifeMateApiException catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } catch (error) {
      debugPrint('WellMate treatment creation failed: $error');
      if (mounted) {
        setState(
          () => _error = LifeMateRuntimeLocale.select(
            fa: 'ثبت درمان انجام نشد. اتصال را بررسی کنید.',
            en: 'The treatment was not recorded. Check the connection.',
          ),
        );
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
      _recurrenceSelection = const TreatmentRecurrenceSelection.explicit();
      _scheduleEditorVersion += 1;
      _patientReminderMinutesBefore =
          LifeMateReminderLeadTimes.defaultPatientMinutes;
      _caregiverReminderMinutesBefore =
          LifeMateReminderLeadTimes.defaultCaregiverMinutes;
      _selectedWeekdays
        ..clear()
        ..addAll(_backendWeekdays.keys);
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomClearance = MediaQuery.paddingOf(context).bottom + 170;
    final sortedZones = _availableTimeZones.toList()..sort();

    return Form(
      key: _formKey,
      child: ListView(
        key: const ValueKey<String>('wellmate-treatment-single-page-form'),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(20, 92, 20, bottomClearance),
        children: [
          Text(
            LifeMateRuntimeLocale.select(fa: 'افزودن درمان', en: 'Add treatment'),
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: AppColors.darkBlue,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            LifeMateRuntimeLocale.select(
              fa: 'همه اطلاعات دارو و برنامه مصرف را در همین صفحه وارد کنید.',
              en: 'Enter the medication and schedule on this page.',
            ),
            style: const TextStyle(color: AppColors.textSecondary, height: 1.5),
          ),
          const SizedBox(height: 18),
          _SectionCard(
            icon: Icons.medication_rounded,
            title: LifeMateRuntimeLocale.select(
              fa: 'مشخصات دارو',
              en: 'Medication details',
            ),
            children: [
              _textField(
                controller: _name,
                label: LifeMateRuntimeLocale.select(fa: 'نام دارو', en: 'Medication name'),
                hint: LifeMateRuntimeLocale.select(fa: 'مثلاً استامینوفن', en: 'For example acetaminophen'),
                icon: Icons.medication_rounded,
                required: true,
              ),
              if (_historyLoading) ...[
                const LinearProgressIndicator(minHeight: 2),
                const SizedBox(height: 8),
              ] else
                Builder(
                  builder: (context) {
                    final suggestions = rankLifeMateHistorySuggestions(
                      history: _medicationHistory,
                      query: _name.text,
                      kind: LifeMateHistorySuggestionKind.medication,
                    );
                    if (suggestions.isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final suggestion in suggestions)
                            ActionChip(
                              key: ValueKey('medication-history-${suggestion.value}'),
                              label: Text('${suggestion.value} · ${suggestion.usageCount}×'),
                              onPressed: _busy
                                  ? null
                                  : () {
                                      _name.value = TextEditingValue(
                                        text: suggestion.value,
                                        selection: TextSelection.collapsed(
                                          offset: suggestion.value.length,
                                        ),
                                      );
                                    },
                            ),
                        ],
                      ),
                    );
                  },
                ),
              _textField(
                controller: _strength,
                label: LifeMateRuntimeLocale.select(fa: 'قدرت دارو', en: 'Strength'),
                hint: LifeMateRuntimeLocale.select(fa: 'مثلاً ۵۰۰ میلی‌گرم', en: 'For example 500 mg'),
                icon: Icons.science_rounded,
              ),
              WellMateLabeledField(
                label: LifeMateRuntimeLocale.select(fa: 'شکل دارو', en: 'Form'),
                icon: Icons.category_rounded,
                child: DropdownButtonFormField<String>(
                  initialValue: _form,
                  isExpanded: true,
                  decoration: wellMateFieldDecoration(),
                  items: [
                    for (final entry in _forms.entries)
                      DropdownMenuItem(value: entry.key, child: Text(entry.value)),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _form = value ?? _form),
                ),
              ),
              _textField(
                controller: _dose,
                label: LifeMateRuntimeLocale.select(fa: 'مقدار مصرف', en: 'Dose'),
                hint: LifeMateRuntimeLocale.select(fa: 'مثلاً ۱ قرص', en: 'For example 1 tablet'),
                icon: Icons.straighten_rounded,
                required: true,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SectionCard(
            icon: Icons.schedule_rounded,
            title: LifeMateRuntimeLocale.select(fa: 'برنامه مصرف', en: 'Schedule'),
            children: [
              TreatmentRecurrenceEditor(
                key: ValueKey('treatment-recurrence-editor-$_scheduleEditorVersion'),
                enabled: !_busy,
                initialAnchor: _times.first,
                onChanged: (value) {
                  if (!mounted) return;
                  setState(() {
                    _recurrenceSelection = value;
                    _error = null;
                  });
                },
              ),
              const SizedBox(height: 16),
              if (!_recurrenceSelection.enabled) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: Text(LifeMateRuntimeLocale.select(fa: 'هر روز', en: 'Every day')),
                      selected: _frequency == 'daily',
                      onSelected: _busy
                          ? null
                          : (_) => setState(() {
                              _frequency = 'daily';
                              _selectedWeekdays
                                ..clear()
                                ..addAll(_backendWeekdays.keys);
                            }),
                    ),
                    ChoiceChip(
                      label: Text(LifeMateRuntimeLocale.select(fa: 'روزهای انتخابی', en: 'Selected days')),
                      selected: _frequency == 'weekly',
                      onSelected: _busy
                          ? null
                          : (_) => setState(() => _frequency = 'weekly'),
                    ),
                  ],
                ),
                if (_frequency == 'weekly') ...[
                  const SizedBox(height: 14),
                  Text(
                    LifeMateRuntimeLocale.select(fa: 'روزهای مصرف', en: 'Days'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
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
                ],
                const SizedBox(height: 16),
                Text(
                  LifeMateRuntimeLocale.select(fa: 'ساعت‌های مصرف', en: 'Times'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var index = 0; index < _times.length; index++)
                      InputChip(
                        label: Text(formatAppTime(context, _times[index])),
                        avatar: const Icon(Icons.access_time_rounded, size: 18),
                        onPressed: _busy ? null : () => _pickTime(replaceIndex: index),
                        onDeleted: _busy || _times.length == 1
                            ? null
                            : () => setState(() => _times.removeAt(index)),
                      ),
                    ActionChip(
                      key: const Key('add-treatment-time'),
                      avatar: const Icon(Icons.add_rounded, size: 18),
                      label: Text(LifeMateRuntimeLocale.select(fa: 'افزودن ساعت', en: 'Add time')),
                      onPressed: _busy ? null : _pickTime,
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              _PickerField(
                label: LifeMateRuntimeLocale.select(fa: 'تاریخ شروع', en: 'Start date'),
                value: formatAppDate(context, _startDate),
                icon: Icons.calendar_today_rounded,
                onTap: _busy ? null : _pickStartDate,
              ),
              _PickerField(
                label: LifeMateRuntimeLocale.select(fa: 'تاریخ پایان', en: 'End date'),
                value: _endDate == null
                    ? LifeMateRuntimeLocale.select(fa: 'بدون تاریخ پایان', en: 'No end date')
                    : formatAppDate(context, _endDate!),
                icon: Icons.event_available_rounded,
                onTap: _busy ? null : _pickEndDate,
                trailing: _endDate == null
                    ? null
                    : IconButton(
                        tooltip: LifeMateRuntimeLocale.select(fa: 'حذف تاریخ پایان', en: 'Remove end date'),
                        onPressed: _busy ? null : () => setState(() => _endDate = null),
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
              const SizedBox(height: 4),
              Text(
                LifeMateRuntimeLocale.select(fa: 'زمان یادآوری', en: 'Reminder lead time'),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              WellMateLabeledField(
                key: const ValueKey('patient-reminder-lead-label'),
                label: LifeMateRuntimeLocale.select(fa: 'یادآوری برای خودم', en: 'Reminder for me'),
                icon: Icons.notifications_active_rounded,
                child: DropdownButtonFormField<int>(
                  key: const ValueKey('patient-reminder-lead'),
                  initialValue: _patientReminderMinutesBefore,
                  isExpanded: true,
                  decoration: wellMateFieldDecoration(),
                  items: [
                    for (final minutes in LifeMateReminderLeadTimes.presets)
                      DropdownMenuItem(
                        value: minutes,
                        child: Text(LifeMateReminderLeadTimes.label(minutes)),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => setState(() {
                          _patientReminderMinutesBefore = value ?? _patientReminderMinutesBefore;
                        }),
                ),
              ),
              WellMateLabeledField(
                key: const ValueKey('caregiver-reminder-lead-label'),
                label: LifeMateRuntimeLocale.select(fa: 'یادآوری برای مراقب', en: 'Reminder for caregiver'),
                icon: Icons.family_restroom_rounded,
                child: DropdownButtonFormField<int>(
                  key: const ValueKey('caregiver-reminder-lead'),
                  initialValue: _caregiverReminderMinutesBefore,
                  isExpanded: true,
                  decoration: wellMateFieldDecoration(),
                  items: [
                    for (final minutes in LifeMateReminderLeadTimes.presets)
                      DropdownMenuItem(
                        value: minutes,
                        child: Text(LifeMateReminderLeadTimes.label(minutes)),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => setState(() {
                          _caregiverReminderMinutesBefore = value ?? _caregiverReminderMinutesBefore;
                        }),
                ),
              ),
              WellMateLabeledField(
                label: LifeMateRuntimeLocale.select(fa: 'منطقه زمانی', en: 'Time zone'),
                icon: Icons.public_rounded,
                bottomSpacing: 0,
                child: DropdownButtonFormField<String>(
                  initialValue: _timeZone,
                  isExpanded: true,
                  decoration: wellMateFieldDecoration(),
                  items: [
                    for (final zone in sortedZones)
                      DropdownMenuItem(value: zone, child: Text(zone)),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _timeZone = value ?? _timeZone),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SectionCard(
            icon: Icons.notes_rounded,
            title: LifeMateRuntimeLocale.select(fa: 'توضیحات', en: 'Notes'),
            children: [
              WellMateLabeledField(
                label: LifeMateRuntimeLocale.select(fa: 'دستور مصرف یا یادداشت', en: 'Instructions or notes'),
                icon: Icons.edit_note_rounded,
                bottomSpacing: 0,
                child: TextFormField(
                  controller: _instructions,
                  minLines: 3,
                  maxLines: 6,
                  decoration: wellMateFieldDecoration(
                    hint: LifeMateRuntimeLocale.select(fa: 'مثلاً بعد از غذا', en: 'For example after food'),
                  ),
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            key: const Key('submit-treatment'),
            width: double.infinity,
            height: 56,
            child: FilledButton.icon(
              onPressed: _busy ? null : _create,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_task_rounded),
              label: Text(
                LifeMateRuntimeLocale.select(fa: 'ثبت درمان', en: 'Save treatment'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    bool required = false,
  }) {
    return WellMateLabeledField(
      label: label,
      icon: icon,
      required: required,
      child: TextFormField(
        controller: controller,
        decoration: wellMateFieldDecoration(hint: hint),
        validator: required
            ? (value) => value?.trim().isNotEmpty == true
                  ? null
                  : LifeMateRuntimeLocale.select(
                      fa: '$label را وارد کنید.',
                      en: 'Enter $label.',
                    )
            : null,
      ),
    );
  }

  static String _friendlyError(LifeMateApiException error) {
    return error.isUnauthorized
        ? LifeMateRuntimeLocale.select(
            fa: 'نشست شما منقضی شده است؛ دوباره وارد شوید.',
            en: 'Your session has expired; sign in again.',
          )
        : LifeMateRuntimeLocale.select(
            fa: 'ثبت درمان انجام نشد. اطلاعات را بررسی و دوباره تلاش کنید.',
            en: 'The treatment was not registered. Check the information and try again.',
          );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.children,
  });

  final IconData icon;
  final String title;
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
            color: AppColors.shadowDark.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
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
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: AppColors.darkBlue,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
    this.trailing,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return WellMateLabeledField(
      label: label,
      icon: icon,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: InputDecorator(
          decoration: wellMateFieldDecoration(suffixIcon: trailing),
          child: Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: AppColors.darkBlue,
            ),
          ),
        ),
      ),
    );
  }
}
