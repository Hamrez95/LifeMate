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

  static const _days = <(String, String)>[
    ('saturday', 'ش'),
    ('sunday', 'ی'),
    ('monday', 'د'),
    ('tuesday', 'س'),
    ('wednesday', 'چ'),
    ('thursday', 'پ'),
    ('friday', 'ج'),
  ];

  @override
  void initState() {
    super.initState();
    final plan = widget.plan;
    final medication =
        plan?['medication'] as Map<String, dynamic>? ?? const <String, dynamic>{};
    _name = TextEditingController(text: medication['name']?.toString() ?? '');
    _strength = TextEditingController(
      text: medication['strengthText']?.toString() ?? '',
    );
    _form = TextEditingController(text: medication['form']?.toString() ?? '');
    _dose = TextEditingController(text: plan?['doseText']?.toString() ?? '');
    _instructions = TextEditingController(
      text: plan?['instructions']?.toString() ?? '',
    );
    _startDate = DateTime.tryParse(plan?['startDate']?.toString() ?? '') ??
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
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .92),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SheetHeader(
              icon: Icons.medication_rounded,
              title: widget.plan == null ? 'افزودن دارو' : 'ویرایش دارو',
            ),
            const SizedBox(height: 16),
            _Input(controller: _name, label: 'نام دارو *'),
            _Input(controller: _strength, label: 'قدرت / غلظت'),
            _Input(controller: _form, label: 'شکل دارویی'),
            _Input(controller: _dose, label: 'مقدار مصرف *'),
            _Input(
              controller: _instructions,
              label: 'دستور و توضیحات',
              maxLines: 3,
            ),
            const SizedBox(height: 4),
            const Text('روزهای مصرف', style: TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 7,
              children: _days.map((day) {
                final selected = _weekdays.contains(day.$1);
                return FilterChip(
                  selected: selected,
                  label: Text(day.$2),
                  onSelected: (value) => setState(() {
                    value ? _weekdays.add(day.$1) : _weekdays.remove(day.$1);
                  }),
                );
              }).toList(growable: false),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _PickerButton(
                    icon: Icons.schedule_rounded,
                    label: 'ساعت ${_time.format(context)}',
                    onTap: _pickTime,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _PickerButton(
                    icon: Icons.calendar_today_rounded,
                    label: 'شروع ${formatAppDate(context, _startDate)}',
                    onTap: _pickStartDate,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _PickerButton(
              icon: Icons.event_available_rounded,
              label: _endDate == null
                  ? 'پایان: بدون تاریخ پایان'
                  : 'پایان ${formatAppDate(context, _endDate!)}',
              onTap: _pickEndDate,
              trailing: _endDate == null
                  ? null
                  : IconButton(
                      tooltip: 'حذف تاریخ پایان',
                      onPressed: () => setState(() => _endDate = null),
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const ValueKey('save-caregiver-medication'),
                onPressed: _submit,
                icon: const Icon(Icons.save_rounded),
                label: const Text('ذخیره در پرونده سلامت'),
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
        title: 'اطلاعات کامل نیست',
        message: 'نام دارو، مقدار مصرف و حداقل یک روز مصرف را وارد کنید.',
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
        schedules: _weekdays
            .map((day) => {'dayOfWeek': day, 'localTime': time})
            .toList(growable: false),
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

  bool get _injection => widget.eventType == 'injection';

  @override
  void initState() {
    super.initState();
    final event = widget.event;
    _title = TextEditingController(text: event?['title']?.toString() ?? '');
    _provider = TextEditingController(text: event?['providerName']?.toString() ?? '');
    _specialty = TextEditingController(text: event?['specialty']?.toString() ?? '');
    _medication = TextEditingController(
      text: event?['medicationName']?.toString() ?? event?['title']?.toString() ?? '',
    );
    _dose = TextEditingController(text: event?['doseText']?.toString() ?? '');
    _reason = TextEditingController(text: event?['reason']?.toString() ?? '');
    _instructions = TextEditingController(text: event?['instructions']?.toString() ?? '');
    _center = TextEditingController(text: event?['centerName']?.toString() ?? '');
    _address = TextEditingController(text: event?['addressLine']?.toString() ?? '');
    _phone = TextEditingController(text: event?['phoneNumber']?.toString() ?? '');
    _date = DateTime.tryParse(event?['scheduledLocalDate']?.toString() ?? '') ?? DateTime.now();
    final rawTime = event?['scheduledLocalTime']?.toString() ?? '09:00';
    final parts = rawTime.split(':');
    _time = TimeOfDay(
      hour: int.tryParse(parts.first) ?? 9,
      minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
    );
    final route = event?['administrationRoute']?.toString().toLowerCase();
    if (const {'intramuscular', 'subcutaneous', 'intravenous', 'other'}.contains(route)) {
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
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .92),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SheetHeader(
              icon: _injection ? Icons.vaccines_rounded : Icons.medical_services_rounded,
              title: widget.event == null
                  ? (_injection ? 'افزودن تزریق' : 'افزودن ویزیت')
                  : (_injection ? 'ویرایش تزریق' : 'ویرایش ویزیت'),
            ),
            const SizedBox(height: 16),
            if (_injection) ...[
              _Input(controller: _medication, label: 'نام داروی تزریقی *'),
              _Input(controller: _dose, label: 'دوز یا مقدار'),
              DropdownButtonFormField<String>(
                value: _route,
                decoration: const InputDecoration(labelText: 'روش تزریق'),
                items: const [
                  DropdownMenuItem(value: 'intramuscular', child: Text('عضلانی')),
                  DropdownMenuItem(value: 'subcutaneous', child: Text('زیرجلدی')),
                  DropdownMenuItem(value: 'intravenous', child: Text('وریدی')),
                  DropdownMenuItem(value: 'other', child: Text('سایر')),
                ],
                onChanged: (value) => setState(() => _route = value ?? _route),
              ),
              const SizedBox(height: 10),
            ] else ...[
              _Input(controller: _title, label: 'عنوان ویزیت *'),
              _Input(controller: _provider, label: 'نام پزشک'),
              _Input(controller: _specialty, label: 'تخصص'),
            ],
            _Input(controller: _reason, label: 'دلیل / توضیح'),
            _Input(controller: _center, label: 'مرکز درمانی'),
            _Input(controller: _address, label: 'آدرس', maxLines: 2),
            _Input(controller: _phone, label: 'شماره تماس', keyboardType: TextInputType.phone),
            _Input(controller: _instructions, label: 'دستور و نکات', maxLines: 3),
            Row(
              children: [
                Expanded(
                  child: _PickerButton(
                    icon: Icons.calendar_today_rounded,
                    label: formatAppDate(context, _date),
                    onTap: _pickDate,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _PickerButton(
                    icon: Icons.schedule_rounded,
                    label: _time.format(context),
                    onTap: _pickTime,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const ValueKey('save-caregiver-care-event'),
                onPressed: _submit,
                icon: const Icon(Icons.save_rounded),
                label: const Text('ذخیره در پرونده سلامت'),
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
        title: 'اطلاعات کامل نیست',
        message: _injection ? 'نام داروی تزریقی را وارد کنید.' : 'عنوان ویزیت را وارد کنید.',
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
        backgroundColor: const Color(0xFFEAF4FF),
        child: Icon(icon, color: AppColors.primaryBlue),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
        ),
      ),
      IconButton(
        tooltip: 'بستن',
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.close_rounded),
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
  });

  final String medicationName;
  final String? strengthText;
  final String? form;
  final String doseText;
  final String? instructions;
  final DateTime startDate;
  final DateTime? endDate;
  final List<Map<String, String>> schedules;
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
}

int _asInt(dynamic value, int fallback) => int.tryParse('$value') ?? fallback;

String? _empty(String value) {
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}
