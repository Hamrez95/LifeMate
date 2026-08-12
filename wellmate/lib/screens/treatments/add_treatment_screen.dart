import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_style.dart';
import '../../core/utils/persian_date_utils.dart';
import '../../core/widgets/labeled_form_field.dart';
import 'treatment_schedule_payload.dart';

/// Kept under the historical class name so existing routes remain compatible.
/// The form is intentionally a single scrollable page; there is no internal
/// timeline or three-step navigation anymore.
class TabbedAddTreatmentScreen extends StatefulWidget {
  const TabbedAddTreatmentScreen({required this.onCreated, super.key});

  final VoidCallback onCreated;

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
  int _patientReminderMinutesBefore =
      LifeMateReminderLeadTimes.defaultPatientMinutes;
  int _caregiverReminderMinutesBefore =
      LifeMateReminderLeadTimes.defaultCaregiverMinutes;
  bool _busy = false;
  bool _profileTimeZoneRequested = false;
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
          fa: LifeMateRuntimeLocale.select(
            fa: 'این ساعت قبلاً به برنامه اضافه شده است.',
            en: "This watch has already been added to the app.",
          ),
          en: "This watch has already been added to the app.",
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
      firstDate: DateTime.now().subtract(Duration(days: 1)),
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

  bool _validateScheduleSelections() {
    if (_selectedWeekdays.isEmpty) {
      setState(
        () => _error = LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'حداقل یک روز هفته را انتخاب کنید.',
            en: "Select at least one day of the week.",
          ),
          en: "Select at least one day of the week.",
        ),
      );
      return false;
    }
    if (_times.isEmpty) {
      setState(
        () => _error = LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'حداقل یک ساعت مصرف را اضافه کنید.',
            en: "Add at least one hour of consumption.",
          ),
          en: "Add at least one hour of consumption.",
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
        patientReminderMinutesBefore: _patientReminderMinutesBefore,
        caregiverReminderMinutesBefore: _caregiverReminderMinutesBefore,
      );
      if (!mounted) return;
      LifeMateNotice.show(
        context,
        type: LifeMateNoticeType.success,
        title: LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'درمان ثبت شد',
            en: "Treatment was recorded",
          ),
          en: "Treatment was recorded",
        ),
        message: LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'برنامه درمان ذخیره شد و برنامه امروز به‌روزرسانی می‌شود.',
            en: "The treatment plan was saved and the plan will be updated today.",
          ),
          en: "The treatment plan was saved and the plan will be updated today.",
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
        key: ValueKey<String>('wellmate-treatment-single-page-form'),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(20, 92, 20, bottomClearance),
        children: [
          Text(
            LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'افزودن درمان',
                en: "Add treatment",
              ),
              en: "Add treatment",
            ),
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: AppColors.darkBlue,
            ),
          ),
          SizedBox(height: 6),
          Text(
            LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'همه اطلاعات دارو و برنامه مصرف را در همین صفحه وارد کنید.',
                en: "Enter all drug information and dosage schedule on this page.",
              ),
              en: "Enter all drug information and dosage schedule on this page.",
            ),
            style: TextStyle(color: AppColors.textSecondary, height: 1.5),
          ),
          SizedBox(height: 18),
          _SectionCard(
            icon: Icons.medication_rounded,
            title: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'مشخصات دارو',
                en: "Drug specifications",
              ),
              en: "Drug specifications",
            ),
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
                    fa: 'مثلاً سیتریزین',
                    en: "For example, cetirizine",
                  ),
                  en: "For example, cetirizine",
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
            ],
          ),
          SizedBox(height: 16),
          _SectionCard(
            icon: Icons.schedule_rounded,
            title: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'برنامه مصرف',
                en: "Consumption plan",
              ),
              en: "Consumption plan",
            ),
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: Text(
                      LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'هر روز',
                          en: "every day",
                        ),
                        en: "every day",
                      ),
                    ),
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
                    label: Text(
                      LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'روزهای انتخابی',
                          en: "Selected days",
                        ),
                        en: "Selected days",
                      ),
                    ),
                    selected: _frequency == 'weekly',
                    onSelected: _busy
                        ? null
                        : (_) => setState(() => _frequency = 'weekly'),
                  ),
                ],
              ),
              if (_frequency == 'weekly') ...[
                SizedBox(height: 14),
                Text(
                  LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'روزهای مصرف',
                      en: "days of use",
                    ),
                    en: "days of use",
                  ),
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 8),
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
              SizedBox(height: 16),
              Text(
                LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'ساعت‌های مصرف',
                    en: "Hours of use",
                  ),
                  en: "Hours of use",
                ),
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 8),
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
                    key: Key('add-treatment-time'),
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
              SizedBox(height: 16),
              _PickerField(
                label: LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'تاریخ شروع',
                    en: "start date",
                  ),
                  en: "start date",
                ),
                value: formatAppDate(context, _startDate),
                icon: Icons.calendar_today_rounded,
                onTap: _busy ? null : _pickStartDate,
              ),
              _PickerField(
                label: LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'تاریخ پایان',
                    en: "end date",
                  ),
                  en: "end date",
                ),
                value: _endDate == null
                    ? LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'بدون تاریخ پایان',
                          en: "No end date",
                        ),
                        en: "No end date",
                      )
                    : formatAppDate(context, _endDate!),
                icon: Icons.event_available_rounded,
                onTap: _busy ? null : _pickEndDate,
                trailing: _endDate == null
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
              SizedBox(height: 4),
              Text(
                LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'زمان یادآوری',
                    en: "Time to remember",
                  ),
                  en: "Time to remember",
                ),
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              SizedBox(height: 12),
              WellMateLabeledField(
                key: ValueKey('patient-reminder-lead-label'),
                label: LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'یادآوری برای خودم',
                    en: "A reminder to myself",
                  ),
                  en: "A reminder to myself",
                ),
                icon: Icons.notifications_active_rounded,
                child: DropdownButtonFormField<int>(
                  key: ValueKey('patient-reminder-lead'),
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
                          _patientReminderMinutesBefore =
                              value ?? _patientReminderMinutesBefore;
                        }),
                ),
              ),
              WellMateLabeledField(
                key: ValueKey('caregiver-reminder-lead-label'),
                label: LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'یادآوری برای مراقب',
                    en: "Reminder for caregivers",
                  ),
                  en: "Reminder for caregivers",
                ),
                icon: Icons.family_restroom_rounded,
                child: DropdownButtonFormField<int>(
                  key: ValueKey('caregiver-reminder-lead'),
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
                    for (final zone in sortedZones)
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
          _SectionCard(
            icon: Icons.notes_rounded,
            title: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'توضیحات',
                en: "Description",
              ),
              en: "Description",
            ),
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
              padding: EdgeInsets.all(12),
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
          SizedBox(height: 20),
          SizedBox(
            key: Key('submit-treatment'),
            width: double.infinity,
            height: 56,
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
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
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
                      fa: LifeMateRuntimeLocale.select(
                        fa: '$label را وارد کنید.',
                        en: "Enter $label.",
                      ),
                      en: "Enter $label.",
                    )
            : null,
      ),
    );
  }

  static String _friendlyError(LifeMateApiException error) {
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
              fa: 'ثبت درمان انجام نشد. اطلاعات را بررسی و دوباره تلاش کنید.',
              en: "The treatment was not registered. Check the information and try again.",
            ),
            en: "The treatment was not registered. Check the information and try again.",
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
