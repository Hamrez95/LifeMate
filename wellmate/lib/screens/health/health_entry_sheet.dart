import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_style.dart';
import '../../core/utils/persian_date_utils.dart';

enum HealthEntryType {
  weight,
  height,
  bloodPressure,
  bloodGlucose,
  heartRate,
  sleep,
  note,
}

class HealthEntryDraft {
  const HealthEntryDraft({
    required this.type,
    required this.valuePrimary,
    required this.valueSecondary,
    required this.note,
    required this.localDateTime,
  });

  final HealthEntryType type;
  final double? valuePrimary;
  final double? valueSecondary;
  final String? note;
  final DateTime localDateTime;

  String get observationType => switch (type) {
    HealthEntryType.weight => 'weight',
    HealthEntryType.height => 'height',
    HealthEntryType.bloodPressure => 'blood_pressure',
    HealthEntryType.bloodGlucose => 'blood_glucose',
    HealthEntryType.heartRate => 'heart_rate',
    HealthEntryType.sleep => 'sleep_duration',
    HealthEntryType.note => 'note',
  };
}

class HealthEntrySheet extends StatefulWidget {
  const HealthEntrySheet({
    super.key,
    required this.type,
    required this.onSubmit,
  });

  final HealthEntryType type;
  final Future<void> Function(HealthEntryDraft draft) onSubmit;

  @override
  State<HealthEntrySheet> createState() => _HealthEntrySheetState();
}

class _HealthEntrySheetState extends State<HealthEntrySheet> {
  final _formKey = GlobalKey<FormState>();
  final _primaryController = TextEditingController();
  final _secondaryController = TextEditingController();
  final _minutesController = TextEditingController();
  final _noteController = TextEditingController();
  late DateTime _selectedDate;
  late TimeOfDay _selectedTime;
  bool _saving = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
    _selectedTime = TimeOfDay.fromDateTime(now);
  }

  @override
  void dispose() {
    _primaryController.dispose();
    _secondaryController.dispose();
    _minutesController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
          child: Container(
            constraints: BoxConstraints(maxHeight: media.size.height * 0.9),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FBF9),
              borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 46,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD8E4DE),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _Header(type: widget.type),
                          const SizedBox(height: 22),
                          _buildFields(),
                          const SizedBox(height: 16),
                          _DateTimeCard(
                            date: _selectedDate,
                            time: _selectedTime,
                            onDateTap: _pickDate,
                            onTimeTap: _pickTime,
                          ),
                          if (_submitError != null) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF1F1),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(
                                _submitError!,
                                style: const TextStyle(
                                  color: Color(0xFFB42318),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            key: const ValueKey('health-entry-save'),
                            onPressed: _saving ? null : _submit,
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(54),
                              backgroundColor: AppColors.primary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(17),
                              ),
                            ),
                            icon: _saving
                                ? const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.4,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.check_rounded),
                            label: Text(
                              _saving ? 'در حال ثبت…' : 'ثبت در سلامت من',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFields() {
    final numberFormatters = <TextInputFormatter>[
      FilteringTextInputFormatter.allow(RegExp(r'[0-9۰-۹\.\,]')),
    ];
    switch (widget.type) {
      case HealthEntryType.bloodPressure:
        return Row(
          children: [
            Expanded(
              child: _MetricField(
                controller: _secondaryController,
                label: 'دیاستول',
                hint: 'مثلاً ۷۶',
                suffix: 'mmHg',
                formatters: numberFormatters,
                validator: (value) => _validateNumber(value, 20, 200),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricField(
                controller: _primaryController,
                label: 'سیستول',
                hint: 'مثلاً ۱۱۸',
                suffix: 'mmHg',
                formatters: numberFormatters,
                validator: (value) => _validateNumber(value, 40, 300),
              ),
            ),
          ],
        );
      case HealthEntryType.sleep:
        return Row(
          children: [
            Expanded(
              child: _MetricField(
                controller: _minutesController,
                label: 'دقیقه',
                hint: '۱۲',
                suffix: 'دقیقه',
                formatters: numberFormatters,
                validator: (value) => _validateNumber(value, 0, 59),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricField(
                controller: _primaryController,
                label: 'ساعت',
                hint: '۷',
                suffix: 'ساعت',
                formatters: numberFormatters,
                validator: (value) => _validateNumber(value, 0, 24),
              ),
            ),
          ],
        );
      case HealthEntryType.note:
        return TextFormField(
          controller: _noteController,
          minLines: 4,
          maxLines: 7,
          maxLength: 500,
          textInputAction: TextInputAction.newline,
          decoration: const InputDecoration(
            labelText: 'یادداشت سلامت',
            hintText: 'هر چیزی که دوست داری برای این روز یادت بماند…',
            prefixIcon: Icon(Icons.notes_rounded),
          ),
          validator: (value) => value == null || value.trim().isEmpty
              ? 'یادداشت نمی‌تواند خالی باشد.'
              : null,
        );
      case HealthEntryType.weight:
        return _MetricField(
          controller: _primaryController,
          label: 'وزن',
          hint: 'مثلاً ۷۸.۴',
          suffix: 'کیلوگرم',
          formatters: numberFormatters,
          validator: (value) => _validateNumber(value, 1, 500),
        );
      case HealthEntryType.height:
        return _MetricField(
          controller: _primaryController,
          label: 'قد',
          hint: 'مثلاً ۱۷۰',
          suffix: 'سانتی‌متر',
          formatters: numberFormatters,
          validator: (value) => _validateNumber(value, 30, 250),
        );
      case HealthEntryType.bloodGlucose:
        return _MetricField(
          controller: _primaryController,
          label: 'قند خون',
          hint: 'مثلاً ۹۵',
          suffix: 'mg/dL',
          formatters: numberFormatters,
          validator: (value) => _validateNumber(value, 20, 1000),
        );
      case HealthEntryType.heartRate:
        return _MetricField(
          controller: _primaryController,
          label: 'ضربان قلب',
          hint: 'مثلاً ۷۲',
          suffix: 'ضربه/دقیقه',
          formatters: numberFormatters,
          validator: (value) => _validateNumber(value, 20, 300),
        );
    }
  }

  String? _validateNumber(String? value, double min, double max) {
    final parsed = _parseNumber(value);
    if (parsed == null) return 'یک مقدار معتبر وارد کن.';
    if (parsed < min || parsed > max) return 'مقدار واردشده خارج از بازه است.';
    return null;
  }

  double? _parseNumber(String? value) {
    if (value == null) return null;
    var normalized = value.trim().replaceAll(',', '.').replaceAll('،', '.');
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    for (var index = 0; index < persian.length; index++) {
      normalized = normalized.replaceAll(persian[index], '$index');
    }
    return double.tryParse(normalized);
  }

  Future<void> _pickDate() async {
    final value = await showAppDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 3650)),
      lastDate: DateTime.now(),
      title: 'تاریخ ثبت اطلاعات',
    );
    if (value != null && mounted) setState(() => _selectedDate = value);
  }

  Future<void> _pickTime() async {
    final value = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      helpText: 'زمان ثبت اطلاعات',
    );
    if (value != null && mounted) setState(() => _selectedTime = value);
  }

  Future<void> _submit() async {
    setState(() => _submitError = null);
    if (!_formKey.currentState!.validate()) return;

    double? primary;
    double? secondary;
    String? note;
    if (widget.type == HealthEntryType.note) {
      note = _noteController.text.trim();
    } else if (widget.type == HealthEntryType.sleep) {
      final hours = _parseNumber(_primaryController.text) ?? 0;
      final minutes = _parseNumber(_minutesController.text) ?? 0;
      primary = hours + (minutes / 60);
      if (primary > 24) {
        setState(
          () => _submitError = 'مدت خواب نمی‌تواند بیشتر از ۲۴ ساعت باشد.',
        );
        return;
      }
    } else {
      primary = _parseNumber(_primaryController.text);
      secondary = widget.type == HealthEntryType.bloodPressure
          ? _parseNumber(_secondaryController.text)
          : null;
      if (widget.type == HealthEntryType.bloodPressure &&
          primary != null &&
          secondary != null &&
          primary <= secondary) {
        setState(() => _submitError = 'عدد سیستول باید از دیاستول بیشتر باشد.');
        return;
      }
    }

    final localDateTime = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );
    if (localDateTime.isAfter(DateTime.now().add(const Duration(minutes: 5)))) {
      setState(() => _submitError = 'زمان ثبت نمی‌تواند در آینده باشد.');
      return;
    }

    setState(() => _saving = true);
    try {
      await widget.onSubmit(
        HealthEntryDraft(
          type: widget.type,
          valuePrimary: primary,
          valueSecondary: secondary,
          note: note,
          localDateTime: localDateTime,
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _submitError =
              'ثبت اطلاعات انجام نشد. اتصال را بررسی و دوباره تلاش کن.';
        });
      }
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.type});

  final HealthEntryType type;

  @override
  Widget build(BuildContext context) {
    final data = _entryPresentation(type);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: data.color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(data.icon, color: data.color, size: 28),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                data.title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                data.subtitle,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'بستن',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    );
  }
}

class _MetricField extends StatelessWidget {
  const _MetricField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.suffix,
    required this.formatters,
    required this.validator,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final String suffix;
  final List<TextInputFormatter> formatters;
  final FormFieldValidator<String> validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: formatters,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixText: suffix,
        suffixStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
      validator: validator,
    );
  }
}

class _DateTimeCard extends StatelessWidget {
  const _DateTimeCard({
    required this.date,
    required this.time,
    required this.onDateTap,
    required this.onTimeTap,
  });

  final DateTime date;
  final TimeOfDay time;
  final VoidCallback onDateTap;
  final VoidCallback onTimeTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _DateTimeButton(
              icon: Icons.access_time_rounded,
              label: 'زمان',
              value: formatAppTime(context, time),
              onTap: onTimeTap,
            ),
          ),
          Container(width: 1, height: 42, color: const Color(0xFFE9EEEB)),
          Expanded(
            child: _DateTimeButton(
              icon: Icons.calendar_today_rounded,
              label: 'تاریخ',
              value: formatAppDate(context, date),
              onTap: onDateTap,
            ),
          ),
        ],
      ),
    );
  }
}

class _DateTimeButton extends StatelessWidget {
  const _DateTimeButton({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppColors.primary, size: 20),
            const SizedBox(width: 8),
            Flexible(
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
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
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

class _EntryPresentation {
  const _EntryPresentation(this.title, this.subtitle, this.icon, this.color);
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
}

_EntryPresentation _entryPresentation(HealthEntryType type) => switch (type) {
  HealthEntryType.weight => const _EntryPresentation(
    'ثبت وزن',
    'وزنت را برای دیدن روند تغییرات ثبت کن',
    Icons.monitor_weight_rounded,
    Color(0xFF48B9C7),
  ),
  HealthEntryType.height => const _EntryPresentation(
    'ثبت قد',
    'قد برای محاسبه شاخص توده بدنی استفاده می‌شود',
    Icons.height_rounded,
    Color(0xFF6EA7EB),
  ),
  HealthEntryType.bloodPressure => const _EntryPresentation(
    'ثبت فشار خون',
    'سیستول و دیاستول را همان‌طور که دستگاه نشان می‌دهد وارد کن',
    Icons.water_drop_rounded,
    Color(0xFFFF8A4C),
  ),
  HealthEntryType.bloodGlucose => const _EntryPresentation(
    'ثبت قند خون',
    'مقدار اندازه‌گیری‌شده را همراه تاریخ و زمان نگه دار',
    Icons.bloodtype_rounded,
    Color(0xFFFF9A58),
  ),
  HealthEntryType.heartRate => const _EntryPresentation(
    'ثبت ضربان قلب',
    'تعداد ضربان در دقیقه را وارد کن',
    Icons.favorite_rounded,
    Color(0xFFF26C7D),
  ),
  HealthEntryType.sleep => const _EntryPresentation(
    'ثبت خواب',
    'مدت خواب این شب را ثبت کن',
    Icons.bedtime_rounded,
    Color(0xFF956CE6),
  ),
  HealthEntryType.note => const _EntryPresentation(
    'یادداشت سلامت',
    'احساس، علامت یا نکته‌ای که برایت مهم است ثبت کن',
    Icons.notes_rounded,
    Color(0xFF8D72D7),
  ),
};
