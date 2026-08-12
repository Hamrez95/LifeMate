import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_style.dart';
import '../../core/utils/persian_date_utils.dart';
import 'package:lifemate_client/lifemate_client.dart';

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
      textDirection: LifeMateRuntimeLocale.isPersian
          ? TextDirection.rtl
          : TextDirection.ltr,
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
                                color: Color(0xFFFFF1F1),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(
                                _submitError!,
                                style: TextStyle(
                                  color: Color(0xFFB42318),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                          SizedBox(height: 20),
                          FilledButton.icon(
                            key: ValueKey('health-entry-save'),
                            onPressed: _saving ? null : _submit,
                            style: FilledButton.styleFrom(
                              minimumSize: Size.fromHeight(54),
                              backgroundColor: AppColors.primary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(17),
                              ),
                            ),
                            icon: _saving
                                ? SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.4,
                                      color: Colors.white,
                                    ),
                                  )
                                : Icon(Icons.check_rounded),
                            label: Text(
                              _saving
                                  ? LifeMateRuntimeLocale.select(
                                      fa: LifeMateRuntimeLocale.select(
                                        fa: 'در حال ثبت…',
                                        en: "Saving…",
                                      ),
                                      en: "Saving…",
                                    )
                                  : LifeMateRuntimeLocale.select(
                                      fa: LifeMateRuntimeLocale.select(
                                        fa: 'ثبت در سلامت من',
                                        en: "Save to My Health",
                                      ),
                                      en: "Save to My Health",
                                    ),
                              style: TextStyle(fontWeight: FontWeight.w900),
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
      const LifeMateLocaleDigitInputFormatter(),
    ];
    switch (widget.type) {
      case HealthEntryType.bloodPressure:
        return Row(
          children: [
            Expanded(
              child: _MetricField(
                controller: _secondaryController,
                label: LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'دیاستول',
                    en: "diastole",
                  ),
                  en: "diastole",
                ),
                hint: LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'مثلاً ۷۶',
                    en: "For example, 76",
                  ),
                  en: "For example, 76",
                ),
                suffix: 'mmHg',
                formatters: numberFormatters,
                validator: (value) => _validateNumber(value, 20, 200),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: _MetricField(
                controller: _primaryController,
                label: LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(fa: 'سیستول', en: "systole"),
                  en: "systole",
                ),
                hint: LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'مثلاً ۱۱۸',
                    en: "For example, 118",
                  ),
                  en: "For example, 118",
                ),
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
                label: LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(fa: 'دقیقه', en: "minutes"),
                  en: "minutes",
                ),
                hint: LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(fa: '۱۲', en: "12"),
                  en: "12",
                ),
                suffix: LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(fa: 'دقیقه', en: "minutes"),
                  en: "minutes",
                ),
                formatters: numberFormatters,
                validator: (value) => _validateNumber(value, 0, 59),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: _MetricField(
                controller: _primaryController,
                label: LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(fa: 'ساعت', en: "hour"),
                  en: "hour",
                ),
                hint: LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(fa: '۷', en: "7"),
                  en: "7",
                ),
                suffix: LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(fa: 'ساعت', en: "hour"),
                  en: "hour",
                ),
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
          decoration: InputDecoration(
            labelText: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'یادداشت سلامت',
                en: "health note",
              ),
              en: "health note",
            ),
            hintText: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'هر چیزی که دوست داری برای این روز یادت بماند…',
                en: "Whatever you want to remember for this day…",
              ),
              en: "Whatever you want to remember for this day…",
            ),
            prefixIcon: Icon(Icons.notes_rounded),
          ),
          validator: (value) => value == null || value.trim().isEmpty
              ? LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'یادداشت نمی‌تواند خالی باشد.',
                    en: "Note cannot be empty.",
                  ),
                  en: "Note cannot be empty.",
                )
              : null,
        );
      case HealthEntryType.weight:
        return _MetricField(
          controller: _primaryController,
          label: LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(fa: 'وزن', en: "weight"),
            en: "weight",
          ),
          hint: LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'مثلاً ۷۸.۴',
              en: "For example, 78.4",
            ),
            en: "For example, 78.4",
          ),
          suffix: LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(fa: 'کیلوگرم', en: "kg"),
            en: "kg",
          ),
          formatters: numberFormatters,
          validator: (value) => _validateNumber(value, 1, 500),
        );
      case HealthEntryType.height:
        return _MetricField(
          controller: _primaryController,
          label: LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(fa: 'قد', en: "height"),
            en: "height",
          ),
          hint: LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'مثلاً ۱۷۰',
              en: "For example, 170",
            ),
            en: "For example, 170",
          ),
          suffix: LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(fa: 'سانتی‌متر', en: "cm"),
            en: "cm",
          ),
          formatters: numberFormatters,
          validator: (value) => _validateNumber(value, 30, 250),
        );
      case HealthEntryType.bloodGlucose:
        return _MetricField(
          controller: _primaryController,
          label: LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(fa: 'قند خون', en: "blood sugar"),
            en: "blood sugar",
          ),
          hint: LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'مثلاً ۹۵',
              en: "For example, 95",
            ),
            en: "For example, 95",
          ),
          suffix: 'mg/dL',
          formatters: numberFormatters,
          validator: (value) => _validateNumber(value, 20, 1000),
        );
      case HealthEntryType.heartRate:
        return _MetricField(
          controller: _primaryController,
          label: LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(fa: 'ضربان قلب', en: "heartbeat"),
            en: "heartbeat",
          ),
          hint: LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'مثلاً ۷۲',
              en: "For example, 72",
            ),
            en: "For example, 72",
          ),
          suffix: LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'ضربه/دقیقه',
              en: "hit/minute",
            ),
            en: "hit/minute",
          ),
          formatters: numberFormatters,
          validator: (value) => _validateNumber(value, 20, 300),
        );
    }
  }

  String? _validateNumber(String? value, double min, double max) {
    final parsed = _parseNumber(value);
    if (parsed == null)
      return LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'یک مقدار معتبر وارد کن.',
          en: "Enter a valid value.",
        ),
        en: "Enter a valid value.",
      );
    if (parsed < min || parsed > max)
      return LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'مقدار واردشده خارج از بازه است.',
          en: "The entered value is out of range.",
        ),
        en: "The entered value is out of range.",
      );
    return null;
  }

  double? _parseNumber(String? value) {
    if (value == null) return null;
    var normalized = value
        .trim()
        .replaceAll(',', '.')
        .replaceAll(
          LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(fa: '،', en: ","),
            en: ",",
          ),
          '.',
        );
    final persian = LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: '۰۱۲۳۴۵۶۷۸۹', en: "0123456789"),
      en: "0123456789",
    );
    for (var index = 0; index < persian.length; index++) {
      normalized = normalized.replaceAll(persian[index], '$index');
    }
    return double.tryParse(normalized);
  }

  Future<void> _pickDate() async {
    final value = await showAppDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(Duration(days: 3650)),
      lastDate: DateTime.now(),
      title: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'تاریخ ثبت اطلاعات',
          en: "Data registration date",
        ),
        en: "Data registration date",
      ),
    );
    if (value != null && mounted) setState(() => _selectedDate = value);
  }

  Future<void> _pickTime() async {
    final value = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      helpText: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'زمان ثبت اطلاعات',
          en: "Time to record information",
        ),
        en: "Time to record information",
      ),
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
          () => _submitError = LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'مدت خواب نمی‌تواند بیشتر از ۲۴ ساعت باشد.',
              en: "The duration of sleep cannot be more than 24 hours.",
            ),
            en: "The duration of sleep cannot be more than 24 hours.",
          ),
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
        setState(
          () => _submitError = LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'عدد سیستول باید از دیاستول بیشتر باشد.',
              en: "The number of systole should be greater than diastole.",
            ),
            en: "The number of systole should be greater than diastole.",
          ),
        );
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
      setState(
        () => _submitError = LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'زمان ثبت نمی‌تواند در آینده باشد.',
            en: "The recording time cannot be in the future.",
          ),
          en: "The recording time cannot be in the future.",
        ),
      );
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
          _submitError = LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'ثبت اطلاعات انجام نشد. اتصال را بررسی و دوباره تلاش کن.',
              en: "Data registration was not done. Check the connection and try again.",
            ),
            en: "Data registration was not done. Check the connection and try again.",
          );
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
        SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                data.title,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary,
                ),
              ),
              SizedBox(height: 3),
              Text(
                data.subtitle,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(fa: 'بستن', en: "to close"),
            en: "to close",
          ),
          onPressed: () => Navigator.of(context).pop(),
          icon: Icon(Icons.close_rounded),
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
      padding: EdgeInsets.all(14),
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
              label: LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(fa: 'زمان', en: "time"),
                en: "time",
              ),
              value: formatAppTime(context, time),
              onTap: onTimeTap,
            ),
          ),
          Container(width: 1, height: 42, color: Color(0xFFE9EEEB)),
          Expanded(
            child: _DateTimeButton(
              icon: Icons.calendar_today_rounded,
              label: LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(fa: 'تاریخ', en: "date"),
                en: "date",
              ),
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
  HealthEntryType.weight => _EntryPresentation(
    LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'ثبت وزن', en: "Record weight"),
      en: "Record weight",
    ),
    LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'وزنت را برای دیدن روند تغییرات ثبت کن',
        en: "Record your weight to see the changes",
      ),
      en: "Record your weight to see the changes",
    ),
    Icons.monitor_weight_rounded,
    Color(0xFF48B9C7),
  ),
  HealthEntryType.height => _EntryPresentation(
    LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'ثبت قد', en: "Record height"),
      en: "Record height",
    ),
    LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'قد برای محاسبه شاخص توده بدنی استفاده می‌شود',
        en: "Height is used to calculate body mass index",
      ),
      en: "Height is used to calculate body mass index",
    ),
    Icons.height_rounded,
    Color(0xFF6EA7EB),
  ),
  HealthEntryType.bloodPressure => _EntryPresentation(
    LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'ثبت فشار خون',
        en: "Record blood pressure",
      ),
      en: "Record blood pressure",
    ),
    LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'سیستول و دیاستول را همان‌طور که دستگاه نشان می‌دهد وارد کن',
        en: "Enter systole and diastole as shown by the device",
      ),
      en: "Enter systole and diastole as shown by the device",
    ),
    Icons.water_drop_rounded,
    Color(0xFFFF8A4C),
  ),
  HealthEntryType.bloodGlucose => _EntryPresentation(
    LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'ثبت قند خون',
        en: "Record blood sugar",
      ),
      en: "Record blood sugar",
    ),
    LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'مقدار اندازه‌گیری‌شده را همراه تاریخ و زمان نگه دار',
        en: "Save the measured value along with the date and time",
      ),
      en: "Save the measured value along with the date and time",
    ),
    Icons.bloodtype_rounded,
    Color(0xFFFF9A58),
  ),
  HealthEntryType.heartRate => _EntryPresentation(
    LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'ثبت ضربان قلب',
        en: "Heart rate recording",
      ),
      en: "Heart rate recording",
    ),
    LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'تعداد ضربان در دقیقه را وارد کن',
        en: "Enter the number of beats per minute",
      ),
      en: "Enter the number of beats per minute",
    ),
    Icons.favorite_rounded,
    Color(0xFFF26C7D),
  ),
  HealthEntryType.sleep => _EntryPresentation(
    LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'ثبت خواب', en: "sleep register"),
      en: "sleep register",
    ),
    LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'مدت خواب این شب را ثبت کن',
        en: "Record the duration of sleep this night",
      ),
      en: "Record the duration of sleep this night",
    ),
    Icons.bedtime_rounded,
    Color(0xFF956CE6),
  ),
  HealthEntryType.note => _EntryPresentation(
    LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'یادداشت سلامت', en: "health note"),
      en: "health note",
    ),
    LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'احساس، علامت یا نکته‌ای که برایت مهم است ثبت کن',
        en: "Record the feeling, sign or point that is important to you",
      ),
      en: "Record the feeling, sign or point that is important to you",
    ),
    Icons.notes_rounded,
    Color(0xFF8D72D7),
  ),
};
