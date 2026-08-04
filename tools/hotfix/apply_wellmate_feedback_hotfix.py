from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]


def write(path: str, content: str) -> None:
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content.rstrip() + "\n", encoding="utf-8")


def replace(path: str, old: str, new: str) -> None:
    target = ROOT / path
    text = target.read_text(encoding="utf-8")
    if old not in text:
        raise RuntimeError(f"Expected block not found in {path}: {old[:100]!r}")
    target.write_text(text.replace(old, new, 1), encoding="utf-8")


write(
    "wellmate/lib/core/utils/persian_date_utils.dart",
    r'''import 'package:flutter/material.dart';
import 'package:shamsi_date/shamsi_date.dart';

import 'string_extensions.dart';

const List<String> _persianMonthNames = <String>[
  'فروردین',
  'اردیبهشت',
  'خرداد',
  'تیر',
  'مرداد',
  'شهریور',
  'مهر',
  'آبان',
  'آذر',
  'دی',
  'بهمن',
  'اسفند',
];

const Map<int, String> _persianWeekdayNames = <int, String>{
  DateTime.saturday: 'شنبه',
  DateTime.sunday: 'یکشنبه',
  DateTime.monday: 'دوشنبه',
  DateTime.tuesday: 'سه‌شنبه',
  DateTime.wednesday: 'چهارشنبه',
  DateTime.thursday: 'پنجشنبه',
  DateTime.friday: 'جمعه',
};

bool usesPersianCalendar(BuildContext context) =>
    Localizations.localeOf(context).languageCode == 'fa';

String localizeDigits(BuildContext context, Object? value) =>
    (value?.toString() ?? '').toPersianDigit(usesPersianCalendar(context));

String formatAppDate(
  BuildContext context,
  DateTime date, {
  bool includeWeekday = false,
}) {
  if (!usesPersianCalendar(context)) {
    return MaterialLocalizations.of(context).formatMediumDate(date);
  }
  final jalali = Jalali.fromDateTime(date);
  final numeric = '${jalali.year.toString().padLeft(4, '0')}/'
          '${jalali.month.toString().padLeft(2, '0')}/'
          '${jalali.day.toString().padLeft(2, '0')}'
      .toPersianDigit(true);
  if (!includeWeekday) return numeric;
  return '${_persianWeekdayNames[date.weekday] ?? ''} $numeric'.trim();
}

String formatAppMonth(BuildContext context, DateTime date) {
  if (!usesPersianCalendar(context)) {
    return MaterialLocalizations.of(context).formatMonthYear(date);
  }
  final jalali = Jalali.fromDateTime(date);
  return '${_persianMonthNames[jalali.month - 1]} ${jalali.year}'
      .toPersianDigit(true);
}

String formatAppTime(BuildContext context, TimeOfDay time) {
  final value = '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';
  return value.toPersianDigit(usesPersianCalendar(context));
}

(DateTime, DateTime) visibleCalendarMonthRange(
  BuildContext context,
  DateTime focusedDate,
) {
  if (!usesPersianCalendar(context)) {
    return (
      DateTime(focusedDate.year, focusedDate.month, 1),
      DateTime(focusedDate.year, focusedDate.month + 1, 0),
    );
  }
  final focused = Jalali.fromDateTime(focusedDate);
  final first = Jalali(focused.year, focused.month, 1);
  final last = Jalali(focused.year, focused.month, first.monthLength);
  return (first.toDateTime(), last.toDateTime());
}

bool isSameVisibleCalendarMonth(
  BuildContext context,
  DateTime left,
  DateTime right,
) {
  if (!usesPersianCalendar(context)) {
    return left.year == right.year && left.month == right.month;
  }
  final leftJalali = Jalali.fromDateTime(left);
  final rightJalali = Jalali.fromDateTime(right);
  return leftJalali.year == rightJalali.year &&
      leftJalali.month == rightJalali.month;
}

Future<DateTime?> showAppDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  String title = 'انتخاب تاریخ',
}) {
  if (!usesPersianCalendar(context)) {
    return showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
    );
  }

  final initial = Jalali.fromDateTime(initialDate);
  final first = Jalali.fromDateTime(firstDate);
  final last = Jalali.fromDateTime(lastDate);
  var year = initial.year;
  var month = initial.month;
  var day = initial.day;
  String? validationError;

  return showDialog<DateTime>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) {
        final monthLength = Jalali(year, month, 1).monthLength;
        if (day > monthLength) day = monthLength;

        void confirm() {
          final selected = Jalali(year, month, day).toDateTime();
          final selectedOnly = DateTime(selected.year, selected.month, selected.day);
          final firstOnly = DateTime(firstDate.year, firstDate.month, firstDate.day);
          final lastOnly = DateTime(lastDate.year, lastDate.month, lastDate.day);
          if (selectedOnly.isBefore(firstOnly) || selectedOnly.isAfter(lastOnly)) {
            setDialogState(() {
              validationError = 'تاریخ انتخاب‌شده خارج از بازه مجاز است.';
            });
            return;
          }
          Navigator.of(dialogContext).pop(selectedOnly);
        }

        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Text(title),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: DropdownButtonFormField<int>(
                          initialValue: year,
                          decoration: const InputDecoration(
                            labelText: 'سال',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            for (var value = first.year; value <= last.year; value++)
                              DropdownMenuItem(
                                value: value,
                                child: Text('$value'.toPersianDigit(true)),
                              ),
                          ],
                          onChanged: (value) => setDialogState(() {
                            year = value ?? year;
                            validationError = null;
                          }),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 4,
                        child: DropdownButtonFormField<int>(
                          initialValue: month,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'ماه',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            for (var value = 1; value <= 12; value++)
                              DropdownMenuItem(
                                value: value,
                                child: Text(_persianMonthNames[value - 1]),
                              ),
                          ],
                          onChanged: (value) => setDialogState(() {
                            month = value ?? month;
                            validationError = null;
                          }),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<int>(
                          initialValue: day,
                          decoration: const InputDecoration(
                            labelText: 'روز',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            for (var value = 1; value <= monthLength; value++)
                              DropdownMenuItem(
                                value: value,
                                child: Text('$value'.toPersianDigit(true)),
                              ),
                          ],
                          onChanged: (value) => setDialogState(() {
                            day = value ?? day;
                            validationError = null;
                          }),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${_persianWeekdayNames[Jalali(year, month, day).toDateTime().weekday] ?? ''}، '
                    '${day.toString().toPersianDigit(true)} '
                    '${_persianMonthNames[month - 1]} '
                    '${year.toString().toPersianDigit(true)}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (validationError != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      validationError!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('انصراف'),
              ),
              FilledButton(
                onPressed: confirm,
                child: const Text('تأیید'),
              ),
            ],
          ),
        );
      },
    ),
  );
}
''',
)

write(
    "wellmate/lib/screens/treatments/add_treatment_screen.dart",
    r'''import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_style.dart';
import '../../core/utils/persian_date_utils.dart';
import 'treatment_schedule_payload.dart';

/// Kept under the historical class name so existing routes remain compatible.
/// The form is intentionally a single scrollable page; there is no internal
/// timeline or three-step navigation anymore.
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
    final initial = replaceIndex == null
        ? (_times.isEmpty ? TimeOfDay.now() : _times.last)
        : _times[replaceIndex];
    final value = await showTimePicker(context: context, initialTime: initial);
    if (value == null || !mounted) return;

    final duplicate = _times.asMap().entries.any(
          (entry) => entry.key != replaceIndex &&
              entry.value.hour == value.hour &&
              entry.value.minute == value.minute,
        );
    if (duplicate) {
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

  Future<void> _pickStartDate() async {
    final value = await showAppDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
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

  bool _validateScheduleSelections() {
    if (_selectedWeekdays.isEmpty) {
      setState(() => _error = 'حداقل یک روز هفته را انتخاب کنید.');
      return false;
    }
    if (_times.isEmpty) {
      setState(() => _error = 'حداقل یک ساعت مصرف را اضافه کنید.');
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
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('درمان ثبت شد و برنامه امروز به‌روزرسانی شد.'),
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
          const Text(
            'افزودن درمان',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: AppColors.darkBlue,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'همه اطلاعات دارو و برنامه مصرف را در همین صفحه وارد کنید.',
            style: TextStyle(color: AppColors.textSecondary, height: 1.5),
          ),
          const SizedBox(height: 18),
          _SectionCard(
            icon: Icons.medication_rounded,
            title: 'مشخصات دارو',
            children: [
              _textField(
                controller: _name,
                label: 'نام دارو',
                hint: 'مثلاً سیتریزین',
                icon: Icons.medication_rounded,
                required: true,
              ),
              _textField(
                controller: _strength,
                label: 'قدرت دارو',
                hint: 'مثلاً ۱۰ میلی‌گرم',
                icon: Icons.science_rounded,
              ),
              DropdownButtonFormField<String>(
                initialValue: _form,
                isExpanded: true,
                decoration: _decoration(
                  label: 'شکل دارو',
                  icon: Icons.category_rounded,
                ),
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
              const SizedBox(height: 12),
              _textField(
                controller: _dose,
                label: 'مقدار مصرف',
                hint: 'مثلاً ۱ قرص',
                icon: Icons.straighten_rounded,
                required: true,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SectionCard(
            icon: Icons.schedule_rounded,
            title: 'برنامه مصرف',
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('هر روز'),
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
                    label: const Text('روزهای انتخابی'),
                    selected: _frequency == 'weekly',
                    onSelected: _busy
                        ? null
                        : (_) => setState(() => _frequency = 'weekly'),
                  ),
                ],
              ),
              if (_frequency == 'weekly') ...[
                const SizedBox(height: 14),
                const Text(
                  'روزهای مصرف',
                  style: TextStyle(fontWeight: FontWeight.w800),
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
              const Text(
                'ساعت‌های مصرف',
                style: TextStyle(fontWeight: FontWeight.w800),
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
                    label: const Text('افزودن ساعت'),
                    onPressed: _busy ? null : _pickTime,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _PickerField(
                label: 'تاریخ شروع',
                value: formatAppDate(context, _startDate),
                icon: Icons.calendar_today_rounded,
                onTap: _busy ? null : _pickStartDate,
              ),
              const SizedBox(height: 12),
              _PickerField(
                label: 'تاریخ پایان',
                value: _endDate == null
                    ? 'بدون تاریخ پایان'
                    : formatAppDate(context, _endDate!),
                icon: Icons.event_available_rounded,
                onTap: _busy ? null : _pickEndDate,
                trailing: _endDate == null
                    ? null
                    : IconButton(
                        tooltip: 'حذف تاریخ پایان',
                        onPressed: _busy ? null : () => setState(() => _endDate = null),
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _timeZone,
                isExpanded: true,
                decoration: _decoration(
                  label: 'منطقه زمانی',
                  icon: Icons.public_rounded,
                ),
                items: [
                  for (final zone in sortedZones)
                    DropdownMenuItem(value: zone, child: Text(zone)),
                ],
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _timeZone = value ?? _timeZone),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SectionCard(
            icon: Icons.notes_rounded,
            title: 'توضیحات',
            children: [
              TextFormField(
                controller: _instructions,
                minLines: 3,
                maxLines: 6,
                decoration: _decoration(
                  label: 'دستور مصرف یا یادداشت',
                  icon: Icons.edit_note_rounded,
                  hint: 'مثلاً بعد از غذا',
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
              label: const Text(
                'ثبت درمان',
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        decoration: _decoration(label: label, icon: icon, hint: hint),
        validator: required
            ? (value) => value?.trim().isNotEmpty == true
                ? null
                : '$label را وارد کنید.'
            : null,
      ),
    );
  }

  static InputDecoration _decoration({
    required String label,
    required IconData icon,
    String? hint,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: AppColors.background.withValues(alpha: 0.65),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
    );
  }

  static String _friendlyError(LifeMateApiException error) {
    return error.isUnauthorized
        ? 'نشست شما منقضی شده است؛ دوباره وارد شوید.'
        : 'ثبت درمان انجام نشد. اطلاعات را بررسی و دوباره تلاش کنید.';
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
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: AppColors.darkBlue,
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          suffixIcon: trailing,
          filled: true,
          fillColor: AppColors.background.withValues(alpha: 0.65),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        ),
        child: Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}
''',
)

write(
    "wellmate/lib/screens/calendar/custom_table_calendar.dart",
    r'''import 'package:flutter/material.dart';
import 'package:shamsi_date/shamsi_date.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../core/theme/app_style.dart';
import '../../core/utils/persian_date_utils.dart';
import '../../core/utils/string_extensions.dart';

class CustomTableCalendar extends StatelessWidget {
  const CustomTableCalendar({
    required this.focusedMonth,
    required this.selectedDate,
    required this.isPersian,
    required this.onDaySelected,
    required this.getDayEventTypes,
    this.onPageChanged,
    super.key,
  });

  final DateTime focusedMonth;
  final DateTime selectedDate;
  final bool isPersian;
  final void Function(DateTime, DateTime) onDaySelected;
  final ValueChanged<DateTime>? onPageChanged;
  final Set<String> Function(DateTime) getDayEventTypes;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(25),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadowDark,
            offset: Offset(5, 5),
            blurRadius: 15,
          ),
          BoxShadow(
            color: AppColors.shadowLight,
            offset: Offset(-5, -5),
            blurRadius: 15,
          ),
        ],
      ),
      child: isPersian
          ? _PersianMonthGrid(
              focusedMonth: focusedMonth,
              selectedDate: selectedDate,
              onDaySelected: onDaySelected,
              onPageChanged: onPageChanged,
              getDayEventTypes: getDayEventTypes,
            )
          : _GregorianCalendar(
              focusedMonth: focusedMonth,
              selectedDate: selectedDate,
              onDaySelected: onDaySelected,
              onPageChanged: onPageChanged,
              getDayEventTypes: getDayEventTypes,
            ),
    );
  }
}

class _PersianMonthGrid extends StatelessWidget {
  const _PersianMonthGrid({
    required this.focusedMonth,
    required this.selectedDate,
    required this.onDaySelected,
    required this.onPageChanged,
    required this.getDayEventTypes,
  });

  final DateTime focusedMonth;
  final DateTime selectedDate;
  final void Function(DateTime, DateTime) onDaySelected;
  final ValueChanged<DateTime>? onPageChanged;
  final Set<String> Function(DateTime) getDayEventTypes;

  static const weekDays = <String>['ش', 'ی', 'د', 'س', 'چ', 'پ', 'ج'];

  DateTime _moveMonth(int delta) {
    final current = Jalali.fromDateTime(focusedMonth);
    var year = current.year;
    var month = current.month + delta;
    if (month < 1) {
      year -= 1;
      month = 12;
    } else if (month > 12) {
      year += 1;
      month = 1;
    }
    return Jalali(year, month, 1).toDateTime();
  }

  @override
  Widget build(BuildContext context) {
    final focused = Jalali.fromDateTime(focusedMonth);
    final firstJalali = Jalali(focused.year, focused.month, 1);
    final firstDate = firstJalali.toDateTime();
    final monthLength = firstJalali.monthLength;
    final leadingEmptyCells = (firstDate.weekday + 1) % 7;

    return Column(
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'ماه قبل',
              onPressed: () => onPageChanged?.call(_moveMonth(-1)),
              icon: const Icon(Icons.chevron_right_rounded),
            ),
            Expanded(
              child: Text(
                formatAppMonth(context, focusedMonth),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            IconButton(
              tooltip: 'ماه بعد',
              onPressed: () => onPageChanged?.call(_moveMonth(1)),
              icon: const Icon(Icons.chevron_left_rounded),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            for (final label in weekDays)
              Expanded(
                child: Center(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: leadingEmptyCells + monthLength,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            childAspectRatio: 0.92,
          ),
          itemBuilder: (context, index) {
            if (index < leadingEmptyCells) return const SizedBox.shrink();
            final day = index - leadingEmptyCells + 1;
            final gregorian = Jalali(focused.year, focused.month, day).toDateTime();
            return _CalendarCell(
              day: gregorian,
              label: '$day'.toPersianDigit(true),
              selected: _sameDay(gregorian, selectedDate),
              today: _sameDay(gregorian, DateTime.now()),
              eventTypes: getDayEventTypes(gregorian),
              onTap: () => onDaySelected(gregorian, gregorian),
            );
          },
        ),
      ],
    );
  }
}

class _GregorianCalendar extends StatelessWidget {
  const _GregorianCalendar({
    required this.focusedMonth,
    required this.selectedDate,
    required this.onDaySelected,
    required this.onPageChanged,
    required this.getDayEventTypes,
  });

  final DateTime focusedMonth;
  final DateTime selectedDate;
  final void Function(DateTime, DateTime) onDaySelected;
  final ValueChanged<DateTime>? onPageChanged;
  final Set<String> Function(DateTime) getDayEventTypes;

  @override
  Widget build(BuildContext context) {
    return TableCalendar(
      locale: 'en_US',
      firstDay: DateTime.utc(2020, 1, 1),
      lastDay: DateTime.utc(2035, 12, 31),
      focusedDay: focusedMonth,
      calendarFormat: CalendarFormat.month,
      startingDayOfWeek: StartingDayOfWeek.sunday,
      onDaySelected: onDaySelected,
      onPageChanged: onPageChanged,
      selectedDayPredicate: (day) => _sameDay(selectedDate, day),
      headerStyle: const HeaderStyle(
        formatButtonVisible: false,
        titleCentered: true,
      ),
      calendarBuilders: CalendarBuilders(
        defaultBuilder: (context, day, _) => _CalendarCell(
          day: day,
          label: '${day.day}',
          selected: false,
          today: false,
          eventTypes: getDayEventTypes(day),
          onTap: () => onDaySelected(day, day),
        ),
        todayBuilder: (context, day, _) => _CalendarCell(
          day: day,
          label: '${day.day}',
          selected: false,
          today: true,
          eventTypes: getDayEventTypes(day),
          onTap: () => onDaySelected(day, day),
        ),
        selectedBuilder: (context, day, _) => _CalendarCell(
          day: day,
          label: '${day.day}',
          selected: true,
          today: false,
          eventTypes: getDayEventTypes(day),
          onTap: () => onDaySelected(day, day),
        ),
      ),
    );
  }
}

class _CalendarCell extends StatelessWidget {
  const _CalendarCell({
    required this.day,
    required this.label,
    required this.selected,
    required this.today,
    required this.eventTypes,
    required this.onTap,
  });

  final DateTime day;
  final String label;
  final bool selected;
  final bool today;
  final Set<String> eventTypes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isPast = DateTime(day.year, day.month, day.day)
        .isBefore(DateTime(now.year, now.month, now.day));
    final hasMissed = today && eventTypes.contains('missed');

    return Padding(
      padding: const EdgeInsets.all(3),
      child: Material(
        color: selected ? AppColors.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              border: today && !selected
                  ? Border.all(
                      color: hasMissed ? Colors.orange : AppColors.primary,
                      width: 1.4,
                    )
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: selected
                        ? Colors.white
                        : isPast
                            ? Colors.grey.shade400
                            : AppColors.textPrimary,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                if (eventTypes.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  _EventDots(eventTypes: eventTypes, faded: isPast),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EventDots extends StatelessWidget {
  const _EventDots({required this.eventTypes, required this.faded});

  final Set<String> eventTypes;
  final bool faded;

  @override
  Widget build(BuildContext context) {
    final colors = <Color>[
      if (eventTypes.contains('medicine') || eventTypes.contains('med'))
        AppColors.calDotMedicine,
      if (eventTypes.contains('doctor') || eventTypes.contains('appointment'))
        AppColors.calDotDoctor,
      if (eventTypes.contains('treatment') || eventTypes.contains('injection'))
        AppColors.calDotTreatment,
    ];
    return Opacity(
      opacity: faded ? 0.45 : 1,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final color in colors.take(3))
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              width: 5,
              height: 5,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
        ],
      ),
    );
  }
}

bool _sameDay(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;
''',
)

write(
    "wellmate/lib/screens/calendar/calendar_screen.dart",
    r'''import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_style.dart';
import '../../core/utils/persian_date_utils.dart';
import '../../localization/app_localizations.dart';
import '../../models/schedule_item_model.dart';
import 'custom_table_calendar.dart';
import 'schedule_item_card.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key, this.refreshToken = 0});

  final int refreshToken;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _selectedDate = DateTime.now();
  DateTime _focusedMonth = DateTime.now();
  bool _loading = true;
  String? _error;
  List<ScheduleItemModel> _monthItems = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMonth());
  }

  @override
  void didUpdateWidget(covariant CalendarScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _loadMonth();
  }

  DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

  Future<void> _loadMonth() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<LifeMateApiClient>();
      final range = visibleCalendarMonthRange(context, _focusedMonth);
      final results = await Future.wait<dynamic>([
        api.getTreatmentPlans(),
        api.getDoseOccurrences(fromDate: range.$1, toDate: range.$2),
        api.getCareEvents(fromDate: range.$1, toDate: range.$2),
      ]);
      final plans = results[0] as List<Map<String, dynamic>>;
      final doses = results[1] as List<Map<String, dynamic>>;
      final careEvents = results[2] as List<Map<String, dynamic>>;
      final plansById = <String, Map<String, dynamic>>{
        for (final plan in plans) plan['id'].toString(): plan,
      };
      final items = <ScheduleItemModel>[
        ...doses.map(
          (dose) => _scheduleItemFromDose(
            dose,
            plansById[dose['treatmentPlanId'].toString()] ?? const {},
          ),
        ),
        ...careEvents.map(_scheduleItemFromCareEvent),
      ]..sort((a, b) {
          final dateCompare = (a.startDate ?? _selectedDate)
              .compareTo(b.startDate ?? _selectedDate);
          return dateCompare == 0 ? a.time.compareTo(b.time) : dateCompare;
        });
      if (!mounted) return;
      setState(() {
        _monthItems = items;
        _loading = false;
      });
    } on LifeMateApiException catch (error) {
      _setError(
        error.isUnauthorized
            ? 'نشست شما منقضی شده است. دوباره وارد شوید.'
            : 'تقویم درمان و مراقبت دریافت نشد. دوباره تلاش کنید.',
      );
    } catch (error) {
      debugPrint('WellMate calendar load failed: $error');
      _setError('تقویم درمان و مراقبت دریافت نشد. اتصال را بررسی کنید.');
    }
  }

  ScheduleItemModel _scheduleItemFromDose(
    Map<String, dynamic> dose,
    Map<String, dynamic> plan,
  ) {
    final medication = plan['medication'] is Map<String, dynamic>
        ? plan['medication'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final status = dose['status']?.toString() ?? 'scheduled';
    final rawTime = dose['scheduledLocalTime']?.toString() ?? '';
    final scheduledDate = DateTime.tryParse(
          dose['scheduledLocalDate']?.toString() ?? '',
        ) ??
        DateTime.tryParse(dose['scheduledAtUtc']?.toString() ?? '')?.toLocal() ??
        _selectedDate;
    return ScheduleItemModel(
      id: dose['id']?.toString() ?? '',
      title: medication['name']?.toString().trim().isNotEmpty == true
          ? medication['name'].toString()
          : dose['medicationName']?.toString() ?? 'دارو',
      time: rawTime.length >= 5 ? rawTime.substring(0, 5) : rawTime,
      dosage: plan['doseText']?.toString() ?? dose['doseText']?.toString() ?? '',
      type: 'medicine',
      frequency: 'طبق برنامه درمان',
      isDone: status == 'taken' || status == 'skipped',
      status: status,
      version: dose['version'] is int ? dose['version'] as int : 1,
      scheduledAtUtc:
          DateTime.tryParse(dose['scheduledAtUtc']?.toString() ?? '')?.toUtc(),
      startDate: _dateOnly(scheduledDate),
      intervalDays: 1,
    );
  }

  ScheduleItemModel _scheduleItemFromCareEvent(Map<String, dynamic> event) {
    final eventType = event['eventType']?.toString().toLowerCase();
    final type = eventType == 'injection' ? 'injection' : 'appointment';
    final rawTime = event['scheduledLocalTime']?.toString() ?? '--:--';
    final date = DateTime.tryParse(event['scheduledLocalDate']?.toString() ?? '') ??
        _selectedDate;
    final status = event['status']?.toString().toLowerCase() ?? 'scheduled';
    final details = <String>[
      if (type == 'appointment')
        _nonEmpty(event['providerName']) ?? _nonEmpty(event['specialty']) ?? '',
      if (type == 'injection')
        _nonEmpty(event['doseText']) ??
            _administrationRouteLabel(event['administrationRoute']),
      _nonEmpty(event['centerName']) ?? '',
      _nonEmpty(event['addressLine']) ?? '',
    ].where((value) => value.isNotEmpty).join(' • ');
    return ScheduleItemModel(
      id: event['id']?.toString() ?? '',
      title: _nonEmpty(event['title']) ??
          (type == 'injection' ? 'تزریق' : 'ویزیت'),
      time: rawTime.length >= 5 ? rawTime.substring(0, 5) : rawTime,
      dosage: details,
      type: type,
      frequency: type == 'injection' ? 'تزریق' : 'ویزیت',
      isDone: status == 'completed' || status == 'cancelled',
      status: status,
      version: event['version'] is int ? event['version'] as int : 1,
      startDate: _dateOnly(date),
      intervalDays: 1,
    );
  }

  static String? _nonEmpty(dynamic value) {
    final normalized = value?.toString().trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  static String _administrationRouteLabel(dynamic value) {
    return switch (value?.toString().toLowerCase()) {
      'intramuscular' => 'عضلانی',
      'subcutaneous' => 'زیرجلدی',
      'intravenous' => 'وریدی',
      'other' => 'طبق دستور درمانگر',
      _ => '',
    };
  }

  void _setError(String message) {
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = message;
    });
  }

  bool _isTimePassed(String time, DateTime targetDate) {
    final now = DateTime.now();
    final targetDay = _dateOnly(targetDate);
    final today = _dateOnly(now);
    if (targetDay.isBefore(today)) return true;
    if (targetDay.isAfter(today)) return false;
    final parts = time.split(':');
    if (parts.length < 2) return false;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1].split(' ').first);
    if (hour == null || minute == null) return false;
    return now.isAfter(DateTime(now.year, now.month, now.day, hour, minute));
  }

  List<ScheduleItemModel> _getEventsForDay(DateTime targetDate) {
    final normalized = _dateOnly(targetDate);
    final items = _monthItems
        .where((item) => _dateOnly(item.startDate ?? targetDate) == normalized)
        .toList(growable: false);
    items.sort((a, b) => a.time.compareTo(b.time));
    return items;
  }

  Set<String> _getDayEventTypes(DateTime day) {
    final types = <String>{};
    for (final item in _getEventsForDay(day)) {
      types.add(item.type.isEmpty ? 'medicine' : item.type);
      if (item.type == 'medicine' &&
          (item.status == 'missed' ||
              (!item.isDone && _isTimePassed(item.time, day)))) {
        types.add('missed');
      }
    }
    return types;
  }

  Future<void> _changeMonth(DateTime focusedDay) async {
    setState(() => _focusedMonth = focusedDay);
    await _loadMonth();
  }

  Widget _eventCard(
    BuildContext context,
    ScheduleItemModel item,
    AppLocalizations loc,
    bool isPersian,
  ) {
    final now = DateTime.now();
    final isFuture = _dateOnly(_selectedDate).isAfter(_dateOnly(now));
    final isMedicine = item.type == 'medicine';
    final isMissed = isMedicine &&
        (item.status == 'missed' ||
            (!item.isDone && _isTimePassed(item.time, _selectedDate)));
    final showDoneMark = isMedicine && item.isDone && !isFuture;
    return Padding(
      key: ValueKey<String>('calendar-event-${item.id}'),
      padding: const EdgeInsets.only(bottom: 12),
      child: ScheduleItemCard(
        item: item,
        loc: loc,
        isPersian: isPersian,
        isMissed: isMissed,
        showDone: showDoneMark,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final isPersian = Localizations.localeOf(context).languageCode == 'fa';
    final selectedEvents = _getEventsForDay(_selectedDate);
    final scheduleTitle = isPersian
        ? 'برنامه روز ${formatAppDate(context, _selectedDate, includeWeekday: true)}'
        : '${loc['calendar_schedule_for'] ?? 'Schedule for'} '
            '${formatAppDate(context, _selectedDate)}';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadMonth,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 20, top: 10),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: CustomTableCalendar(
                    focusedMonth: _focusedMonth,
                    selectedDate: _selectedDate,
                    isPersian: isPersian,
                    getDayEventTypes: _getDayEventTypes,
                    onPageChanged: _changeMonth,
                    onDaySelected: (selectedDay, focusedDay) async {
                      final monthChanged = !isSameVisibleCalendarMonth(
                        context,
                        focusedDay,
                        _focusedMonth,
                      );
                      setState(() {
                        _selectedDate = selectedDay;
                        _focusedMonth = focusedDay;
                      });
                      if (monthChanged) await _loadMonth();
                    },
                  ),
                ),
                const SizedBox(height: 25),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.shadowDark.withValues(alpha: 0.5),
                        blurRadius: 10,
                        offset: const Offset(0, -5),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        scheduleTitle,
                        style: AppTextStyles.heading(context).copyWith(fontSize: 18),
                      ),
                      const SizedBox(height: 16),
                      if (_loading)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 48),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_error != null)
                        _CalendarErrorState(message: _error!, onRetry: _loadMonth)
                      else if (selectedEvents.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Center(
                            child: Text(
                              loc['calendar_empty'] ?? 'بدون برنامه',
                              style: AppTextStyles.body(context),
                            ),
                          ),
                        )
                      else
                        Column(
                          key: const ValueKey<String>('calendar-event-list'),
                          children: [
                            for (final item in selectedEvents)
                              _eventCard(context, item, loc, isPersian),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CalendarErrorState extends StatelessWidget {
  const _CalendarErrorState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 34),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 48, color: AppColors.primary),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('تلاش دوباره'),
            ),
          ],
        ),
      ),
    );
  }
}
''',
)

write(
    "wellmate/lib/screens/home/home_screen_content.dart",
    r'''import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_style.dart';
import '../../core/utils/string_extensions.dart';
import '../../localization/app_localizations.dart';
import '../../models/schedule_item_model.dart';
import '../../providers/medication_provider.dart';
import '../../providers/notification_provider.dart';
import 'active_treatment_card.dart';
import 'soft_schedule_card.dart';

class HomeScreenContent extends StatefulWidget {
  const HomeScreenContent({
    super.key,
    required this.onOpenTreatments,
    required this.onAddTreatment,
  });

  final VoidCallback onOpenTreatments;
  final VoidCallback onAddTreatment;

  @override
  State<HomeScreenContent> createState() => _HomeScreenContentState();
}

class _HomeScreenContentState extends State<HomeScreenContent> {
  List<ScheduleItemModel> scheduleList = const [];
  ScheduleItemModel? _nextOccurrence;
  Timer? _timer;
  bool isLoading = true;
  String? loadError;
  String _displayName = '';
  bool _hasTreatmentPlans = false;
  final Set<String> _submitting = <String>{};

  @override
  void initState() {
    super.initState();
    _fetchScheduleFromBackend();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetchScheduleFromBackend() async {
    if (mounted) {
      setState(() {
        isLoading = true;
        loadError = null;
      });
    }
    try {
      final api = context.read<LifeMateApiClient>();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final lastVisibleDay = today.add(const Duration(days: 7));
      final results = await Future.wait<dynamic>([
        api.getCurrentUser(),
        api.getTreatmentPlans(),
        api.getDoseOccurrences(fromDate: today, toDate: lastVisibleDay),
        api.getCareEvents(fromDate: today, toDate: lastVisibleDay),
      ]);
      final currentUser = results[0] as Map<String, dynamic>;
      final plans = results[1] as List<Map<String, dynamic>>;
      final doses = results[2] as List<Map<String, dynamic>>;
      final careEvents = results[3] as List<Map<String, dynamic>>;
      final profile = currentUser['profile'] as Map<String, dynamic>? ?? const {};
      final plansById = <String, Map<String, dynamic>>{
        for (final plan in plans) plan['id'].toString(): plan,
      };

      final allItems = <ScheduleItemModel>[
        ...doses.map((dose) {
          final plan = plansById[dose['treatmentPlanId'].toString()] ?? const {};
          final medication = plan['medication'] is Map<String, dynamic>
              ? plan['medication'] as Map<String, dynamic>
              : const <String, dynamic>{};
          final status = (dose['status'] ?? 'scheduled').toString();
          final rawTime = (dose['scheduledLocalTime'] ?? '').toString();
          final time = rawTime.length >= 5 ? rawTime.substring(0, 5) : rawTime;
          return ScheduleItemModel(
            id: dose['id'].toString(),
            type: 'medicine',
            title: (medication['name'] ?? 'دارو').toString(),
            time: time,
            dosage: (plan['doseText'] ?? '').toString(),
            status: status,
            version: dose['version'] is int ? dose['version'] as int : 1,
            scheduledAtUtc: DateTime.tryParse(
              dose['scheduledAtUtc']?.toString() ?? '',
            )?.toUtc(),
            isDone: status == 'taken' || status == 'skipped',
            frequency: 'طبق برنامه درمان',
            startDate: dose['scheduledLocalDate'] == null
                ? today
                : DateTime.tryParse(dose['scheduledLocalDate'].toString()),
            intervalDays: 1,
          );
        }),
        ...careEvents.map((event) {
          final eventType = event['eventType']?.toString().toLowerCase();
          final type = eventType == 'injection' ? 'injection' : 'appointment';
          final rawTime = event['scheduledLocalTime']?.toString() ?? '--:--';
          final status = event['status']?.toString().toLowerCase() ?? 'scheduled';
          final details = <String>[
            if (type == 'appointment')
              _nonEmpty(event['providerName']) ?? _nonEmpty(event['specialty']) ?? '',
            if (type == 'injection') _nonEmpty(event['doseText']) ?? '',
            _nonEmpty(event['centerName']) ?? '',
          ].where((value) => value.isNotEmpty).join(' • ');
          return ScheduleItemModel(
            id: event['id']?.toString() ?? '',
            type: type,
            title: _nonEmpty(event['title']) ??
                (type == 'injection' ? 'تزریق' : 'ویزیت'),
            time: rawTime.length >= 5 ? rawTime.substring(0, 5) : rawTime,
            dosage: details,
            status: status,
            version: event['version'] is int ? event['version'] as int : 1,
            isDone: status == 'completed' || status == 'cancelled',
            frequency: type == 'injection' ? 'تزریق' : 'ویزیت',
            startDate: DateTime.tryParse(
              event['scheduledLocalDate']?.toString() ?? '',
            ),
            intervalDays: 1,
          );
        }),
      ]..sort(_compareOccurrence);

      final todayItems = allItems.where((item) {
        final date = item.startDate;
        return date != null && _sameDay(date, today);
      }).toList(growable: false);
      final actionable = allItems.where((item) {
        if (item.type == 'medicine') {
          return item.status == 'scheduled' || item.status == 'missed';
        }
        return item.status != 'completed' && item.status != 'cancelled';
      }).toList(growable: false);
      final future = actionable.where((item) {
        final scheduled = _scheduledDateTime(item);
        return scheduled != null && !scheduled.isBefore(DateTime.now());
      }).toList(growable: false)
        ..sort(_compareOccurrence);
      final missedMedicine = actionable.where(
        (item) => item.type == 'medicine' && item.status == 'missed',
      );
      final nextOccurrence = future.isNotEmpty
          ? future.first
          : (missedMedicine.isNotEmpty ? missedMedicine.first : null);

      if (!mounted) return;
      setState(() {
        _displayName = profile['displayName']?.toString().trim() ?? '';
        scheduleList = todayItems;
        _nextOccurrence = nextOccurrence;
        _hasTreatmentPlans = plans.isNotEmpty;
        isLoading = false;
      });

      final medicineToday = todayItems
          .where((item) => item.type == 'medicine')
          .toList(growable: false);
      context.read<MedicationProvider>().setMedications(medicineToday);
      try {
        await context.read<NotificationProvider>().syncDoseReminders(
              medicineToday,
              timeZone: profile['timeZone']?.toString() ?? 'Asia/Tehran',
            );
      } catch (error) {
        debugPrint('WellMate reminder sync failed: $error');
      }
    } catch (error) {
      debugPrint('WellMate home schedule sync failed: $error');
      if (!mounted) return;
      setState(() {
        isLoading = false;
        loadError = 'برنامه امروز دریافت نشد. اتصال را بررسی کنید.';
      });
    }
  }

  Future<void> _reportStatus(ScheduleItemModel item, String status) async {
    if (item.type != 'medicine' || _submitting.contains(item.id)) return;
    setState(() => _submitting.add(item.id));
    try {
      final result = await context.read<LifeMateApiClient>().reportDose(
            occurrenceId: item.id,
            clientRequestId: LifeMateApiClient.createClientRequestId(),
            version: item.version,
            status: status,
            occurredAtUtc: DateTime.now().toUtc(),
          );
      if (!mounted) return;
      final updated = item.copyWith(
        isDone: status == 'taken' || status == 'skipped',
        status: (result['status'] ?? status).toString(),
        version: result['version'] is int
            ? result['version'] as int
            : item.version + 1,
      );
      setState(() {
        final index = scheduleList.indexWhere((value) => value.id == item.id);
        if (index >= 0) scheduleList[index] = updated;
        if (_nextOccurrence?.id == item.id) _nextOccurrence = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == 'taken'
                ? '${item.title} به عنوان مصرف‌شده ثبت شد.'
                : '${item.title} به عنوان مصرف‌نشده ثبت شد.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _fetchScheduleFromBackend();
    } catch (error) {
      debugPrint('WellMate dose report failed: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ثبت مصرف انجام نشد؛ دوباره تلاش کنید.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting.remove(item.id));
    }
  }

  int _calculateSecondsLeft(ScheduleItemModel item) {
    final scheduled = _scheduledDateTime(item);
    if (scheduled == null) return 0;
    final seconds = scheduled.difference(DateTime.now()).inSeconds;
    return seconds > 0 ? seconds : 0;
  }

  String _getAssetPath(String type) {
    switch (type) {
      case 'appointment':
      case 'visit':
        return 'assets/icons/stethoscope.png';
      case 'drop':
        return 'assets/icons/water_drop.png';
      default:
        return 'assets/icons/pill.png';
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final font = AppTextStyles.body(context);
    final isPersian = Localizations.localeOf(context).languageCode == 'fa';
    final visibleToday = scheduleList.where((item) => !item.isDone).toList()
      ..sort(_compareOccurrence);
    final nextItem = _nextOccurrence;

    return Container(
      color: AppColors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(24, 20, 24, 16),
            child: Text(
              isPersian
                  ? (_displayName.isEmpty ? 'سلام،' : 'سلام $_displayName جان،')
                  : (_displayName.isEmpty ? 'Hello,' : 'Hi $_displayName,'),
              style: font.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          if (isLoading)
            const Expanded(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (loadError != null)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_rounded, size: 52),
                    const SizedBox(height: 12),
                    Text(loadError!, textAlign: TextAlign.center),
                    const SizedBox(height: 14),
                    FilledButton(
                      onPressed: _fetchScheduleFromBackend,
                      child: const Text('تلاش دوباره'),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: nextItem == null
                  ? _TreatmentTimerPlaceholder(
                      hasTreatmentPlans: _hasTreatmentPlans,
                      onAction: _hasTreatmentPlans
                          ? widget.onOpenTreatments
                          : widget.onAddTreatment,
                      font: font,
                    )
                  : nextItem.type == 'medicine'
                      ? ActiveTreatmentCard(
                          treatmentName: nextItem.title,
                          dose: nextItem.dosage,
                          time: nextItem.time,
                          assetIconPath: _getAssetPath(nextItem.type),
                          progressValue: 1.0 -
                              (_calculateSecondsLeft(nextItem) / 86400)
                                  .clamp(0.0, 1.0),
                          secondsLeft: _calculateSecondsLeft(nextItem),
                          onTaken: _submitting.contains(nextItem.id)
                              ? null
                              : () => _reportStatus(nextItem, 'taken'),
                          onSkipped: _submitting.contains(nextItem.id)
                              ? null
                              : () => _reportStatus(nextItem, 'skipped'),
                          onEdit: widget.onOpenTreatments,
                          isSubmitting: _submitting.contains(nextItem.id),
                          font: font,
                        )
                      : _UpcomingCareEventCard(
                          item: nextItem,
                          secondsLeft: _calculateSecondsLeft(nextItem),
                          assetPath: _getAssetPath(nextItem.type),
                          font: font,
                        ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(24, 24, 24, 16),
                      child: Text(
                        loc['today_schedule'] ?? 'برنامه امروز',
                        style: font.copyWith(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Expanded(
                      child: visibleToday.isEmpty
                          ? _HomeEmptyState(
                              hasTreatmentPlans: _hasTreatmentPlans,
                              onAddTreatment: widget.onAddTreatment,
                              font: font,
                            )
                          : RefreshIndicator(
                              onRefresh: _fetchScheduleFromBackend,
                              child: ListView.separated(
                                padding: const EdgeInsetsDirectional.fromSTEB(
                                  24,
                                  0,
                                  24,
                                  110,
                                ),
                                itemCount: visibleToday.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 12),
                                itemBuilder: (context, index) {
                                  final item = visibleToday[index];
                                  final missed = item.type == 'medicine' &&
                                      item.status == 'missed';
                                  return SoftScheduleCard(
                                    item: item,
                                    index: index,
                                    font: font,
                                    assetPath: _getAssetPath(item.type),
                                    isMissed: missed,
                                    onTaken: missed &&
                                            !_submitting.contains(item.id)
                                        ? () => _reportStatus(item, 'taken')
                                        : null,
                                  );
                                },
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String? _nonEmpty(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static DateTime? _scheduledDateTime(ScheduleItemModel item) {
    if (item.scheduledAtUtc != null) return item.scheduledAtUtc!.toLocal();
    final date = item.startDate;
    final parts = item.time.split(':');
    if (date == null || parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1].split(' ').first);
    if (hour == null || minute == null) return null;
    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  static int _compareOccurrence(ScheduleItemModel left, ScheduleItemModel right) {
    final leftDate = _scheduledDateTime(left) ?? DateTime(2100);
    final rightDate = _scheduledDateTime(right) ?? DateTime(2100);
    return leftDate.compareTo(rightDate);
  }

  static bool _sameDay(DateTime left, DateTime right) =>
      left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

class _UpcomingCareEventCard extends StatelessWidget {
  const _UpcomingCareEventCard({
    required this.item,
    required this.secondsLeft,
    required this.assetPath,
    required this.font,
  });

  final ScheduleItemModel item;
  final int secondsLeft;
  final String assetPath;
  final TextStyle font;

  String _countdown(bool persian) {
    final minutes = secondsLeft ~/ 60;
    if (minutes < 60) return '$minutes دقیقه دیگر'.toPersianDigit(persian);
    final hours = minutes ~/ 60;
    final remaining = minutes % 60;
    return '$hours ساعت و $remaining دقیقه دیگر'.toPersianDigit(persian);
  }

  @override
  Widget build(BuildContext context) {
    final persian = Localizations.localeOf(context).languageCode == 'fa';
    final kind = item.type == 'injection' ? 'زمان تزریق' : 'وقت ویزیت';
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowDark.withValues(alpha: 0.35),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 92,
            height: 92,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Image.asset(
              assetPath,
              errorBuilder: (_, __, ___) => Icon(
                item.type == 'injection'
                    ? Icons.vaccines_rounded
                    : Icons.medical_services_rounded,
                color: AppColors.primary,
                size: 44,
              ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  kind,
                  style: font.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  item.title,
                  style: font.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppColors.darkBlue,
                  ),
                ),
                if (item.dosage.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(item.dosage, maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
                const SizedBox(height: 8),
                Text(
                  '${item.time} • ${_countdown(persian)}'
                      .toPersianDigit(persian),
                  style: font.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TreatmentTimerPlaceholder extends StatelessWidget {
  const _TreatmentTimerPlaceholder({
    required this.hasTreatmentPlans,
    required this.onAction,
    required this.font,
  });

  final bool hasTreatmentPlans;
  final VoidCallback onAction;
  final TextStyle font;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 48,
            backgroundColor: Color(0xFFF1FAF5),
            child: Icon(Icons.medication_rounded, size: 44, color: AppColors.primary),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasTreatmentPlans
                      ? 'برنامه بعدی در اینجا نمایش داده می‌شود'
                      : 'تایمر درمان آماده است',
                  style: font.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppColors.darkBlue,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  hasTreatmentPlans
                      ? 'برای دیدن جزئیات، برنامه درمان را باز کنید.'
                      : 'پس از ثبت اولین دارو یا ویزیت، شمارش معکوس اینجا دیده می‌شود.',
                  style: font.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: onAction,
                  icon: const Icon(Icons.add_rounded),
                  label: Text(hasTreatmentPlans ? 'درمان‌ها' : 'افزودن برنامه'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeEmptyState extends StatelessWidget {
  const _HomeEmptyState({
    required this.hasTreatmentPlans,
    required this.onAddTreatment,
    required this.font,
  });

  final bool hasTreatmentPlans;
  final VoidCallback onAddTreatment;
  final TextStyle font;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 110),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircleAvatar(
              radius: 48,
              backgroundColor: Color(0xFFE7F8F1),
              child: Icon(Icons.medication_liquid_rounded, size: 48, color: AppColors.primary),
            ),
            const SizedBox(height: 18),
            Text(
              hasTreatmentPlans
                  ? 'برای امروز برنامه‌ای باقی نمانده است.'
                  : 'هنوز برنامه درمانی ثبت نشده است.',
              textAlign: TextAlign.center,
              style: font.copyWith(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              hasTreatmentPlans
                  ? 'برنامه‌های دارویی، ویزیت و تزریق بعدی به‌صورت خودکار نمایش داده می‌شوند.'
                  : 'اولین دارو، ویزیت یا تزریق را اضافه کنید.',
              textAlign: TextAlign.center,
              style: font.copyWith(color: AppColors.textSecondary),
            ),
            if (!hasTreatmentPlans) ...[
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: onAddTreatment,
                icon: const Icon(Icons.add_rounded),
                label: const Text('افزودن برنامه'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
''',
)

# Calendar and home must refresh immediately after any successful creation.
replace(
    "wellmate/lib/screens/home/home_screen.dart",
    "      const CalendarScreen(),",
    "      CalendarScreen(refreshToken: _refreshToken),",
)

# Persian date/time picker and safe bottom clearance for appointment/injection.
replace(
    "wellmate/lib/screens/treatments/care_plan_hub_screen.dart",
    "import '../../core/theme/app_style.dart';\nimport 'add_treatment_screen.dart';",
    "import '../../core/theme/app_style.dart';\nimport '../../core/utils/persian_date_utils.dart';\nimport 'add_treatment_screen.dart';",
)
replace(
    "wellmate/lib/screens/treatments/care_plan_hub_screen.dart",
    """  Future<void> _pickDate() async {\n    final value = await showDatePicker(\n      context: context,\n      initialDate: _date,\n      firstDate: DateTime.now().subtract(const Duration(days: 1)),\n      lastDate: DateTime.now().add(const Duration(days: 3650)),\n    );\n    if (mounted && value != null) setState(() => _date = value);\n  }""",
    """  Future<void> _pickDate() async {\n    final value = await showAppDatePicker(\n      context: context,\n      initialDate: _date,\n      firstDate: DateTime.now().subtract(const Duration(days: 1)),\n      lastDate: DateTime.now().add(const Duration(days: 3650)),\n      title: _isAppointment ? 'تاریخ ویزیت' : 'تاریخ تزریق',\n    );\n    if (mounted && value != null) setState(() => _date = value);\n  }""",
)
replace(
    "wellmate/lib/screens/treatments/care_plan_hub_screen.dart",
    """  String get _dateLabel =>\n      '${_date.year}/${_date.month.toString().padLeft(2, '0')}/'\n      '${_date.day.toString().padLeft(2, '0')}';""",
    "  String get _dateLabel => formatAppDate(context, _date);",
)
replace(
    "wellmate/lib/screens/treatments/care_plan_hub_screen.dart",
    "                    value: _timeValue,",
    "                    value: formatAppTime(context, _time),",
)
replace(
    "wellmate/lib/screens/treatments/care_plan_hub_screen.dart",
    "        padding: const EdgeInsets.fromLTRB(20, 14, 20, 120),",
    "        padding: EdgeInsets.fromLTRB(\n          20,\n          14,\n          20,\n          MediaQuery.paddingOf(context).bottom + 170,\n        ),",
)

# Signup no longer instructs the user to wait for a confirmation email. The
# database trigger applied for this internal phase confirms new email users.
replace(
    "packages/lifemate_client/lib/src/session_gate_secure.dart",
    """            _success =\n                'حساب ساخته شد. ایمیل تأیید را بررسی کنید و سپس وارد شوید.';""",
    "            _success = 'حساب ساخته شد. اکنون می‌توانید وارد شوید.';",
)

# Version bump and generated launcher-icon configuration for both apps.
for app, image in (
    ("wellmate", "assets/images/WellMateWithoutBack.png"),
    ("caremate", "assets/images/CareMateWithoutBack.png"),
):
    pubspec = ROOT / app / "pubspec.yaml"
    text = pubspec.read_text(encoding="utf-8")
    text = re.sub(
        r"^version: .*?$",
        "version: 0.9.0-internal.2+13",
        text,
        count=1,
        flags=re.MULTILINE,
    )
    if "flutter_launcher_icons:" not in text:
        text = text.replace(
            "dev_dependencies:\n  flutter_test:\n    sdk: flutter\n",
            "dev_dependencies:\n  flutter_test:\n    sdk: flutter\n  flutter_launcher_icons: ^0.14.4\n",
            1,
        )
        text = text.replace(
            "\nflutter:\n",
            f"\nflutter_launcher_icons:\n  android: true\n  image_path: {image}\n  adaptive_icon_background: '#F1FAF5'\n  adaptive_icon_foreground: {image}\n  min_sdk_android: 23\n\nflutter:\n",
            1,
        )
    pubspec.write_text(text, encoding="utf-8")

replace(
    "wellmate/lib/core/constants/app_version.dart",
    "const String wellMateAppVersion = '0.9.0-internal.1+12';",
    "const String wellMateAppVersion = '0.9.0-internal.2+13';",
)
replace(
    "caremate/lib/core/constants/app_version.dart",
    "const String careMateAppVersion = '0.9.0-internal.1+12';",
    "const String careMateAppVersion = '0.9.0-internal.2+13';",
)

write(
    "wellmate/test/add_treatment_accessibility_test.dart",
    r'''import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';
import 'package:wellmate/screens/treatments/add_treatment_screen.dart';

void main() {
  testWidgets(
    'single-page treatment form remains scrollable above bottom navigation',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        Provider<LifeMateApiClient>.value(
          value: _ProfileTimeZoneApiClient(),
          child: MaterialApp(
            locale: const Locale('fa'),
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(1.45),
                ),
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: Scaffold(
                    body: TabbedAddTreatmentScreen(onCreated: () {}),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('wellmate-treatment-single-page-form')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('add-treatment-time')), findsOneWidget);
      expect(find.text('منطقه زمانی'), findsOneWidget);
      expect(find.text('Europe/Berlin'), findsOneWidget);
      expect(find.text('دارو'), findsNothing);

      await tester.ensureVisible(find.byKey(const Key('submit-treatment')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('submit-treatment')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

class _ProfileTimeZoneApiClient extends LifeMateApiClient {
  _ProfileTimeZoneApiClient()
      : super(
          baseUri: Uri.parse('https://example.invalid'),
          accessToken: () => 'test-token',
        );

  @override
  Future<Map<String, dynamic>> getCurrentUser() async => {
        'user': {'id': 'patient-1', 'email': 'patient@example.com'},
        'profile': {
          'displayName': 'بیمار تست',
          'locale': 'fa',
          'timeZone': 'Europe/Berlin',
        },
      };
}
''',
)

write(
    "supabase/migrations/20260804090000_enable_internal_email_auto_confirmation.sql",
    r'''-- Internal testing phase only.
-- Keep normal Supabase rate-limited email/password signup, but mark newly
-- inserted email users as confirmed so the apps receive a session immediately
-- and do not require an email-confirmation round trip.
-- Remove this trigger before public launch or when authentication is migrated.
create or replace function public.lifemate_internal_auto_confirm_email()
returns trigger
language plpgsql
security definer
set search_path = auth, pg_temp
as $$
begin
  if new.email is not null and new.email_confirmed_at is null then
    new.email_confirmed_at := now();
  end if;
  return new;
end;
$$;

revoke all on function public.lifemate_internal_auto_confirm_email()
from public, anon, authenticated;

drop trigger if exists lifemate_internal_auto_confirm_email on auth.users;
create trigger lifemate_internal_auto_confirm_email
before insert on auth.users
for each row
execute function public.lifemate_internal_auto_confirm_email();
''',
)

print("WellMate feedback hotfix sources prepared.")
