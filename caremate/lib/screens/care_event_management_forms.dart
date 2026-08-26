part of 'care_event_management_screen.dart';

class _MedicationFormSheet extends StatefulWidget {
  const _MedicationFormSheet({this.plan});

  final Map<String, dynamic>? plan;

  @override
  State<_MedicationFormSheet> createState() => _MedicationFormSheetState();
}

class _MedicationFormSheetState extends State<_MedicationFormSheet> {
  late final TextEditingController _name;
  late final TextEditingController _strength;
  late final TextEditingController _form;
  late final TextEditingController _dose;
  late final TextEditingController _instructions;
  late DateTime _startDate;
  DateTime? _endDate;
  late TimeOfDay _time;
  late Set<String> _weekdays;
  bool _recurrenceEnabled = false;
  int _recurrenceHours = 6;

  static final _days = <(String, String)>[
    (
      'saturday',
      LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(fa: 'ش', en: "Sat"),
        en: "Sat",
      ),
    ),
    (
      'sunday',
      LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(fa: 'ی', en: "Sun"),
        en: "Sun",
      ),
    ),
    (
      'monday',
      LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(fa: 'د', en: "Mon"),
        en: "Mon",
      ),
    ),
    (
      'tuesday',
      LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(fa: 'س', en: "Tue"),
        en: "Tue",
      ),
    ),
    (
      'wednesday',
      LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(fa: 'چ', en: "Wed"),
        en: "Wed",
      ),
    ),
    (
      'thursday',
      LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(fa: 'پ', en: "Thu"),
        en: "Thu",
      ),
    ),
    (
      'friday',
      LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(fa: 'ج', en: "Fri"),
        en: "Fri",
      ),
    ),
  ];

  @override
  void initState() {
    super.initState();
    final plan = widget.plan;
    final medication =
        plan?['medication'] as Map<String, dynamic>? ??
        const <String, dynamic>{};
    _name = TextEditingController(text: medication['name']?.toString() ?? '');
    _strength = TextEditingController(
      text: medication['strengthText']?.toString() ?? '',
    );
    _form = TextEditingController(text: medication['form']?.toString() ?? '');
    _dose = TextEditingController(text: plan?['doseText']?.toString() ?? '');
    _instructions = TextEditingController(
      text: plan?['instructions']?.toString() ?? '',
    );
    _startDate =
        DateTime.tryParse(plan?['startDate']?.toString() ?? '') ??
        DateTime.now();
    _endDate = DateTime.tryParse(plan?['endDate']?.toString() ?? '');
    final schedules = plan?['schedules'] as List<dynamic>? ?? const [];
    _weekdays = schedules
        .map((item) => item is Map ? item['dayOfWeek']?.toString() : null)
        .whereType<String>()
        .map((value) => value.toLowerCase())
        .toSet();
    if (_weekdays.isEmpty) _weekdays = _days.map((item) => item.$1).toSet();
    final rawTime = schedules.isEmpty || schedules.first is! Map
        ? '08:00'
        : (schedules.first as Map)['localTime']?.toString() ?? '08:00';
    final parts = rawTime.split(':');
    _time = TimeOfDay(
      hour: int.tryParse(parts.first) ?? 8,
      minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
    );
    final recurrence = plan?['recurrence'];
    if (recurrence is Map && recurrence['enabled'] == true && recurrence['unit']?.toString() == 'hour') {
      _recurrenceEnabled = true;
      _recurrenceHours = int.tryParse('${recurrence['interval']}') ?? 6;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _strength.dispose();
    _form.dispose();
    _dose.dispose();
    _instructions.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .92,
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottom),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SheetHeader(
              icon: Icons.medication_rounded,
              title: widget.plan == null
                  ? LifeMateRuntimeLocale.select(
                      fa: LifeMateRuntimeLocale.select(
                        fa: 'افزودن دارو',
                        en: "Addition of medicine",
                      ),
                      en: "Addition of medicine",
                    )
                  : LifeMateRuntimeLocale.select(
                      fa: LifeMateRuntimeLocale.select(
                        fa: 'ویرایش دارو',
                        en: "Drug editing",
                      ),
                      en: "Drug editing",
                    ),
            ),
            SizedBox(height: 16),
            _Input(
              controller: _name,
              label: LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'نام دارو *',
                  en: "Drug name *",
                ),
                en: "Drug name *",
              ),
            ),
            _Input(
              controller: _strength,
              label: LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'قدرت / غلظت',
                  en: "Strength/concentration",
                ),
                en: "Strength/concentration",
              ),
            ),
            _Input(
              controller: _form,
              label: LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'شکل دارویی',
                  en: "Pharmaceutical form",
                ),
                en: "Pharmaceutical form",
              ),
            ),
            _Input(
              controller: _dose,
              label: LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'مقدار مصرف *',
                  en: "consumption amount *",
                ),
                en: "consumption amount *",
              ),
            ),
            _Input(
              controller: _instructions,
              label: LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'دستور و توضیحات',
                  en: "Instructions and explanations",
                ),
                en: "Instructions and explanations",
              ),
              maxLines: 3,
            ),
            SizedBox(height: 4),
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
            SizedBox(height: 8),
            Wrap(
              spacing: 7,
              children: _days
                  .map((day) {
                    final selected = _weekdays.contains(day.$1);
                    return FilterChip(
                      selected: selected,
                      label: Text(day.$2),
                      onSelected: (value) => setState(() {
                        value
                            ? _weekdays.add(day.$1)
                            : _weekdays.remove(day.$1);
                      }),
                    );
                  })
                  .toList(growable: false),
            ),
            SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _PickerButton(
                    icon: Icons.schedule_rounded,
                    label: LifeMateRuntimeLocale.select(
                      fa: LifeMateRuntimeLocale.select(
                        fa: 'ساعت ${_time.format(context)}',
                        en: "Clock ${_time.format(context)}",
                      ),
                      en: "Clock ${_time.format(context)}",
                    ),
                    onTap: _pickTime,
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: _PickerButton(
                    icon: Icons.calendar_today_rounded,
                    label: LifeMateRuntimeLocale.select(
                      fa: LifeMateRuntimeLocale.select(
                        fa: 'شروع ${formatAppDate(context, _startDate)}',
                        en: "Start ${formatAppDate(context, _startDate)}",
                      ),
                      en: "Start ${formatAppDate(context, _startDate)}",
                    ),
                    onTap: _pickStartDate,
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            _PickerButton(
              icon: Icons.event_available_rounded,
              label: _endDate == null
                  ? LifeMateRuntimeLocale.select(
                      fa: LifeMateRuntimeLocale.select(
                        fa: 'پایان: بدون تاریخ پایان',
                        en: "End: No end date",
                      ),
                      en: "End: No end date",
                    )
                  : LifeMateRuntimeLocale.select(
                      fa: LifeMateRuntimeLocale.select(
                        fa: 'پایان ${formatAppDate(context, _endDate!)}',
                        en: "End ${formatAppDate(context, _endDate!)}",
                      ),
                      en: "End ${formatAppDate(context, _endDate!)}",
                    ),
              onTap: _pickEndDate,
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
                      onPressed: () => setState(() => _endDate = null),
                      icon: Icon(Icons.close_rounded),
                    ),
            ),
            SwitchListTile.adaptive(
              key: const ValueKey('caremate-medication-recurrence-enabled'),
              contentPadding: EdgeInsets.zero,
              title: Text(LifeMateRuntimeLocale.select(fa: 'تکرار دوره‌ای دارو', en: 'Recurring medication')),
              subtitle: Text(LifeMateRuntimeLocale.select(fa: 'مثال: هر ۶ ساعت از زمان شروع', en: 'Example: every 6 hours from the start time')),
              value: _recurrenceEnabled,
              onChanged: (value) => setState(() => _recurrenceEnabled = value),
            ),
            if (_recurrenceEnabled)
              TextFormField(
                key: const ValueKey('caremate-medication-recurrence-hours'),
                initialValue: _recurrenceHours.toString(),
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: LifeMateRuntimeLocale.select(fa: 'هر چند ساعت', en: 'Every how many hours')),
                onChanged: (value) { final parsed = int.tryParse(value.trim()); if (parsed != null && parsed > 0) _recurrenceHours = parsed; },
              ),
                        SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: ValueKey('save-caregiver-medication'),
                onPressed: _submit,
                icon: Icon(Icons.save_rounded),
                label: Text(
                  LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'ذخیره در پرونده سلامت',
                      en: "Save in health file",
                    ),
                    en: "Save in health file",
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickTime() async {
    final value = await showTimePicker(context: context, initialTime: _time);
    if (value != null) setState(() => _time = value);
  }

  Future<void> _pickStartDate() async {
    final value = await showDatePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 3650)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      initialDate: _startDate,
    );
    if (value != null) setState(() => _startDate = value);
  }

  Future<void> _pickEndDate() async {
    final value = await showDatePicker(
      context: context,
      firstDate: _startDate,
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      initialDate: _endDate ?? _startDate.add(const Duration(days: 30)),
    );
    if (value != null) setState(() => _endDate = value);
  }

  void _submit() {
    if (_name.text.trim().isEmpty ||
        _dose.text.trim().isEmpty ||
        _weekdays.isEmpty) {
      LifeMateNotice.show(
        context,
        type: LifeMateNoticeType.warning,
        title: LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'اطلاعات کامل نیست',
            en: "The information is not complete",
          ),
          en: "The information is not complete",
        ),
        message: LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'نام دارو، مقدار مصرف و حداقل یک روز مصرف را وارد کنید.',
            en: "Enter the name of the drug, dosage and at least one day of use.",
          ),
          en: "Enter the name of the drug, dosage and at least one day of use.",
        ),
      );
      return;
    }
    final time =
        '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}';
    Navigator.of(context).pop(
      _MedicationDraft(
        medicationName: _name.text.trim(),
        strengthText: _empty(_strength.text),
        form: _empty(_form.text),
        doseText: _dose.text.trim(),
        instructions: _empty(_instructions.text),
        startDate: _startDate,
        endDate: _endDate,
        schedules: _recurrenceEnabled ? const [] : _weekdays
            .map((day) => {'dayOfWeek': day, 'localTime': time})
            .toList(growable: false),
        recurrence: _recurrenceEnabled
            ? RecurrenceRule(enabled: true, unit: RecurrenceUnit.hour, interval: _recurrenceHours)
            : const RecurrenceRule.none(),
        recurrenceStartLocalTime: time,
      ),
    );
  }
}

class _CareEventFormSheet extends StatefulWidget {
  const _CareEventFormSheet({required this.eventType, this.event});

  final String eventType;
  final Map<String, dynamic>? event;

  @override
  State<_CareEventFormSheet> createState() => _CareEventFormSheetState();
}

class _CareEventFormSheetState extends State<_CareEventFormSheet> {
  late final TextEditingController _title;
  late final TextEditingController _provider;
  late final TextEditingController _specialty;
  late final TextEditingController _medication;
  late final TextEditingController _dose;
  late final TextEditingController _reason;
  late final TextEditingController _instructions;
  late final TextEditingController _center;
  late final TextEditingController _address;
  late final TextEditingController _phone;
  late DateTime _date;
  late TimeOfDay _time;
  String _route = 'intramuscular';
  bool _recurrenceEnabled = false;
  RecurrenceUnit _recurrenceUnit = RecurrenceUnit.month;
  int _recurrenceInterval = 1;

  bool get _injection => widget.eventType == 'injection';

  @override
  void initState() {
    super.initState();
    final event = widget.event;
    _title = TextEditingController(text: event?['title']?.toString() ?? '');
    _provider = TextEditingController(
      text: event?['providerName']?.toString() ?? '',
    );
    _specialty = TextEditingController(
      text: event?['specialty']?.toString() ?? '',
    );
    _medication = TextEditingController(
      text:
          event?['medicationName']?.toString() ??
          event?['title']?.toString() ??
          '',
    );
    _dose = TextEditingController(text: event?['doseText']?.toString() ?? '');
    _reason = TextEditingController(text: event?['reason']?.toString() ?? '');
    _instructions = TextEditingController(
      text: event?['instructions']?.toString() ?? '',
    );
    _center = TextEditingController(
      text: event?['centerName']?.toString() ?? '',
    );
    _address = TextEditingController(
      text: event?['addressLine']?.toString() ?? '',
    );
    _phone = TextEditingController(
      text: event?['phoneNumber']?.toString() ?? '',
    );
    _date =
        DateTime.tryParse(event?['scheduledLocalDate']?.toString() ?? '') ??
        DateTime.now();
    final rawTime = event?['scheduledLocalTime']?.toString() ?? '09:00';
    final parts = rawTime.split(':');
    _time = TimeOfDay(
      hour: int.tryParse(parts.first) ?? 9,
      minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
    );
    final route = event?['administrationRoute']?.toString().toLowerCase();
    final recurrence = event?['recurrence'];
    if (recurrence is Map && recurrence['enabled'] == true) {
      _recurrenceEnabled = true;
      _recurrenceInterval = int.tryParse('${recurrence['interval']}') ?? 1;
      _recurrenceUnit = switch (recurrence['unit']?.toString()) {
        'hour' => RecurrenceUnit.hour,
        'day' => RecurrenceUnit.day,
        'week' => RecurrenceUnit.week,
        'year' => RecurrenceUnit.year,
        _ => RecurrenceUnit.month,
      };
    }
    if (const {
      'intramuscular',
      'subcutaneous',
      'intravenous',
      'other',
    }.contains(route)) {
      _route = route!;
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _title,
      _provider,
      _specialty,
      _medication,
      _dose,
      _reason,
      _instructions,
      _center,
      _address,
      _phone,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .92,
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottom),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SheetHeader(
              icon: _injection
                  ? Icons.vaccines_rounded
                  : Icons.medical_services_rounded,
              title: widget.event == null
                  ? (_injection
                        ? LifeMateRuntimeLocale.select(
                            fa: LifeMateRuntimeLocale.select(
                              fa: 'افزودن تزریق',
                              en: "Add injection",
                            ),
                            en: "Add injection",
                          )
                        : LifeMateRuntimeLocale.select(
                            fa: LifeMateRuntimeLocale.select(
                              fa: 'افزودن ویزیت',
                              en: "Add a visit",
                            ),
                            en: "Add a visit",
                          ))
                  : (_injection
                        ? LifeMateRuntimeLocale.select(
                            fa: LifeMateRuntimeLocale.select(
                              fa: 'ویرایش تزریق',
                              en: "Edit injection",
                            ),
                            en: "Edit injection",
                          )
                        : LifeMateRuntimeLocale.select(
                            fa: LifeMateRuntimeLocale.select(
                              fa: 'ویرایش ویزیت',
                              en: "Edit visit",
                            ),
                            en: "Edit visit",
                          )),
            ),
            SizedBox(height: 16),
            if (_injection) ...[
              _Input(
                controller: _medication,
                label: LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'نام داروی تزریقی *',
                    en: "name of injectable drug *",
                  ),
                  en: "name of injectable drug *",
                ),
              ),
              _Input(
                controller: _dose,
                label: LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'دوز یا مقدار',
                    en: "Dose or quantity",
                  ),
                  en: "Dose or quantity",
                ),
              ),
              DropdownButtonFormField<String>(
                value: _route,
                decoration: InputDecoration(
                  labelText: LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'روش تزریق',
                      en: "Injection method",
                    ),
                    en: "Injection method",
                  ),
                ),
                items: [
                  DropdownMenuItem(
                    value: 'intramuscular',
                    child: Text(
                      LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'عضلانی',
                          en: "muscular",
                        ),
                        en: "muscular",
                      ),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'subcutaneous',
                    child: Text(
                      LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'زیرجلدی',
                          en: "Undercover",
                        ),
                        en: "Undercover",
                      ),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'intravenous',
                    child: Text(
                      LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'وریدی',
                          en: "vein",
                        ),
                        en: "vein",
                      ),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'other',
                    child: Text(
                      LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'سایر',
                          en: "other",
                        ),
                        en: "other",
                      ),
                    ),
                  ),
                ],
                onChanged: (value) => setState(() => _route = value ?? _route),
              ),
              SizedBox(height: 10),
            ] else ...[
              _Input(
                controller: _title,
                label: LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'عنوان ویزیت *',
                    en: "Title of visit *",
                  ),
                  en: "Title of visit *",
                ),
              ),
              _Input(
                controller: _provider,
                label: LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'نام پزشک',
                    en: "Doctor's name",
                  ),
                  en: "Doctor's name",
                ),
              ),
              _Input(
                controller: _specialty,
                label: LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(fa: 'تخصص', en: "Expertise"),
                  en: "Expertise",
                ),
              ),
            ],
            _Input(
              controller: _reason,
              label: LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'دلیل / توضیح',
                  en: "Reason / explanation",
                ),
                en: "Reason / explanation",
              ),
            ),
            _Input(
              controller: _center,
              label: LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'مرکز درمانی',
                  en: "Treatment center",
                ),
                en: "Treatment center",
              ),
            ),
            _Input(
              controller: _address,
              label: LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(fa: 'آدرس', en: "address"),
                en: "address",
              ),
              maxLines: 2,
            ),
            _Input(
              controller: _phone,
              label: LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'شماره تماس',
                  en: "Contact number",
                ),
                en: "Contact number",
              ),
              keyboardType: TextInputType.phone,
            ),
            _Input(
              controller: _instructions,
              label: LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'دستور و نکات',
                  en: "Instructions and tips",
                ),
                en: "Instructions and tips",
              ),
              maxLines: 3,
            ),
            Row(
              children: [
                Expanded(
                  child: _PickerButton(
                    icon: Icons.calendar_today_rounded,
                    label: formatAppDate(context, _date),
                    onTap: _pickDate,
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: _PickerButton(
                    icon: Icons.schedule_rounded,
                    label: _time.format(context),
                    onTap: _pickTime,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              key: const ValueKey('caremate-recurrence-enabled'),
              contentPadding: EdgeInsets.zero,
              title: Text(LifeMateRuntimeLocale.select(fa: 'تکرار زمان‌بندی', en: 'Repeat schedule')),
              subtitle: Text(LifeMateRuntimeLocale.select(fa: 'فقط نوبت‌های آینده ساخته می‌شوند؛ سابقه قبلی تغییر نمی‌کند.', en: 'Only future occurrences are created; history is preserved.')),
              value: _recurrenceEnabled,
              onChanged: (value) => setState(() => _recurrenceEnabled = value),
            ),
            if (_recurrenceEnabled) ...[
              Row(children: [
                Expanded(child: TextFormField(
                  key: const ValueKey('caremate-recurrence-interval'),
                  initialValue: _recurrenceInterval.toString(),
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: LifeMateRuntimeLocale.select(fa: 'هر چند بار', en: 'Every')),
                  onChanged: (value) { final parsed = int.tryParse(value.trim()); if (parsed != null && parsed > 0) _recurrenceInterval = parsed; },
                )),
                const SizedBox(width: 10),
                Expanded(child: DropdownButtonFormField<RecurrenceUnit>(
                  key: const ValueKey('caremate-recurrence-unit'),
                  value: _recurrenceUnit,
                  decoration: InputDecoration(labelText: LifeMateRuntimeLocale.select(fa: 'واحد', en: 'Unit')),
                  items: const [
                    DropdownMenuItem(value: RecurrenceUnit.hour, child: Text('hour')),
                    DropdownMenuItem(value: RecurrenceUnit.day, child: Text('day')),
                    DropdownMenuItem(value: RecurrenceUnit.week, child: Text('week')),
                    DropdownMenuItem(value: RecurrenceUnit.month, child: Text('month')),
                    DropdownMenuItem(value: RecurrenceUnit.year, child: Text('year')),
                  ],
                  onChanged: (value) { if (value != null) setState(() => _recurrenceUnit = value); },
                )),
              ]),
            ],
            SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: ValueKey('save-caregiver-care-event'),
                onPressed: _submit,
                icon: Icon(Icons.save_rounded),
                label: Text(
                  LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'ذخیره در پرونده سلامت',
                      en: "Save in health file",
                    ),
                    en: "Save in health file",
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final value = await showDatePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 3650)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      initialDate: _date,
    );
    if (value != null) setState(() => _date = value);
  }

  Future<void> _pickTime() async {
    final value = await showTimePicker(context: context, initialTime: _time);
    if (value != null) setState(() => _time = value);
  }

  void _submit() {
    final medicationName = _medication.text.trim();
    final title = _injection ? medicationName : _title.text.trim();
    if (title.isEmpty) {
      LifeMateNotice.show(
        context,
        type: LifeMateNoticeType.warning,
        title: LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'اطلاعات کامل نیست',
            en: "The information is not complete",
          ),
          en: "The information is not complete",
        ),
        message: _injection
            ? LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'نام داروی تزریقی را وارد کنید.',
                  en: "Enter the name of the injectable drug.",
                ),
                en: "Enter the name of the injectable drug.",
              )
            : LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'عنوان ویزیت را وارد کنید.',
                  en: "Enter the title of the visit.",
                ),
                en: "Enter the title of the visit.",
              ),
      );
      return;
    }
    final time =
        '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}';
    Navigator.of(context).pop(
      _CareEventDraft(
        title: title,
        providerName: _empty(_provider.text),
        specialty: _empty(_specialty.text),
        medicationName: _injection ? medicationName : null,
        doseText: _injection ? _empty(_dose.text) : null,
        administrationRoute: _injection ? _route : null,
        reason: _empty(_reason.text),
        instructions: _empty(_instructions.text),
        centerName: _empty(_center.text),
        addressLine: _empty(_address.text),
        phoneNumber: _empty(_phone.text),
        date: _date,
        time: time,
        recurrence: _recurrenceEnabled
            ? RecurrenceRule(enabled: true, unit: _recurrenceUnit, interval: _recurrenceInterval)
            : const RecurrenceRule.none(),
      ),
    );
  }
}

class _Input extends StatelessWidget {
  const _Input({
    required this.controller,
    required this.label,
    this.maxLines = 1,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String label;
  final int maxLines;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      inputFormatters: const [LifeMateLocaleDigitInputFormatter()],
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: const Color(0xFFF7F9FC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    ),
  );
}

class _PickerButton extends StatelessWidget {
  const _PickerButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFFF7F9FC),
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primaryBlue, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    ),
  );
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.icon, required this.title});
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      CircleAvatar(
        backgroundColor: Color(0xFFEAF4FF),
        child: Icon(icon, color: AppColors.primaryBlue),
      ),
      SizedBox(width: 10),
      Expanded(
        child: Text(
          title,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
        ),
      ),
      IconButton(
        tooltip: LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(fa: 'بستن', en: "to close"),
          en: "to close",
        ),
        onPressed: () => Navigator.pop(context),
        icon: Icon(Icons.close_rounded),
      ),
    ],
  );
}

class _MedicationDraft {
  const _MedicationDraft({
    required this.medicationName,
    required this.strengthText,
    required this.form,
    required this.doseText,
    required this.instructions,
    required this.startDate,
    required this.endDate,
    required this.schedules,
    required this.recurrence,
    required this.recurrenceStartLocalTime,
  });

  final String medicationName;
  final String? strengthText;
  final String? form;
  final String doseText;
  final String? instructions;
  final DateTime startDate;
  final DateTime? endDate;
  final List<Map<String, String>> schedules;
  final RecurrenceRule recurrence;
  final String recurrenceStartLocalTime;
}

class _CareEventDraft {
  const _CareEventDraft({
    required this.title,
    required this.providerName,
    required this.specialty,
    required this.medicationName,
    required this.doseText,
    required this.administrationRoute,
    required this.reason,
    required this.instructions,
    required this.centerName,
    required this.addressLine,
    required this.phoneNumber,
    required this.date,
    required this.time,
    required this.recurrence,
  });

  final String title;
  final String? providerName;
  final String? specialty;
  final String? medicationName;
  final String? doseText;
  final String? administrationRoute;
  final String? reason;
  final String? instructions;
  final String? centerName;
  final String? addressLine;
  final String? phoneNumber;
  final DateTime date;
  final String time;
  final RecurrenceRule recurrence;
}

int _asInt(dynamic value, int fallback) => int.tryParse('$value') ?? fallback;

String? _empty(String value) {
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}
