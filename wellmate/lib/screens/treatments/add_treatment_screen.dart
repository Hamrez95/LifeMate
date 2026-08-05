import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_style.dart';
import '../../core/utils/persian_date_utils.dart';
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
                      onPressed: _busy
                          ? null
                          : () => _pickTime(replaceIndex: index),
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
                        onPressed: _busy
                            ? null
                            : () => setState(() => _endDate = null),
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
