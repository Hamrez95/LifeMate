import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:lifemate_ui/lifemate_ui.dart'
    hide LifeMateLocaleDigitInputFormatter;

import '../../core/theme/app_style.dart';
import '../../core/utils/persian_date_utils.dart';
import '../../core/widgets/labeled_form_field.dart';
import 'medication_schedule_preferences_screen.dart';
import 'nearby_dose_optimization_screen.dart';
import 'sleep_schedule_optimization_screen.dart';

class TreatmentRecurrenceSelection {
  const TreatmentRecurrenceSelection.explicit()
    : enabled = false,
      unit = RecurrenceUnit.hour,
      interval = 6,
      anchor = null;

  const TreatmentRecurrenceSelection.interval({
    required this.unit,
    required this.interval,
    required this.anchor,
  }) : enabled = true;

  final bool enabled;
  final RecurrenceUnit unit;
  final int interval;
  final TimeOfDay? anchor;

  RecurrenceRule rule({DateTime? endDate}) {
    if (!enabled) return const RecurrenceRule.none();
    DateTime? recurrenceEnd = endDate;
    if (unit == RecurrenceUnit.hour && endDate != null) {
      recurrenceEnd = DateTime(
        endDate.year,
        endDate.month,
        endDate.day,
        23,
        59,
        59,
      );
    }
    return RecurrenceRule(
      enabled: true,
      unit: unit,
      interval: interval,
      endDate: recurrenceEnd,
    );
  }

  String? get anchorLocalTime {
    final value = anchor;
    if (!enabled || value == null) return null;
    return '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}';
  }
}

class TreatmentRecurrenceEditor extends StatefulWidget {
  const TreatmentRecurrenceEditor({
    required this.enabled,
    required this.initialAnchor,
    required this.onChanged,
    super.key,
  });

  final bool enabled;
  final TimeOfDay initialAnchor;
  final ValueChanged<TreatmentRecurrenceSelection> onChanged;

  @override
  State<TreatmentRecurrenceEditor> createState() =>
      _TreatmentRecurrenceEditorState();
}

class _TreatmentRecurrenceEditorState extends State<TreatmentRecurrenceEditor> {
  static const _hourPresets = <int>[6, 8, 12, 24, 48];

  bool _intervalMode = true;
  RecurrenceUnit _unit = RecurrenceUnit.hour;
  int _interval = 8;
  late TimeOfDay _anchor;

  @override
  void initState() {
    super.initState();
    _anchor = widget.initialAnchor;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _publish();
    });
  }

  void _publish() {
    widget.onChanged(
      _intervalMode
          ? TreatmentRecurrenceSelection.interval(
              unit: _unit,
              interval: _interval,
              anchor: _anchor,
            )
          : const TreatmentRecurrenceSelection.explicit(),
    );
  }

  Future<void> _pickAnchor() async {
    final value = await showTimePicker(context: context, initialTime: _anchor);
    if (value == null || !mounted) return;
    setState(() => _anchor = value);
    _publish();
  }

  Future<void> _openSleepPreferences() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const MedicationSchedulePreferencesScreen(),
      ),
    );
  }

  Future<void> _openNearbyOptimization() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const NearbyDoseOptimizationScreen(),
      ),
    );
  }

  Future<void> _openSleepOptimization() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const SleepScheduleOptimizationScreen(),
      ),
    );
  }

  void _selectHourPreset(int hours) {
    setState(() {
      _intervalMode = true;
      _unit = RecurrenceUnit.hour;
      _interval = hours;
    });
    _publish();
  }

  String _presetLabel(int hours) {
    return switch (hours) {
      6 => context.tr('medication.schedule.interval.sixHours'),
      8 => context.tr('medication.schedule.interval.eightHours'),
      12 => context.tr('medication.schedule.interval.twelveHours'),
      24 => context.tr('medication.schedule.interval.daily'),
      48 => context.tr('medication.schedule.interval.twoDays'),
      _ => '$hours h',
    };
  }

  String _unitLabel(RecurrenceUnit unit) {
    return switch (unit) {
      RecurrenceUnit.hour =>
        LifeMateRuntimeLocale.select(fa: 'ساعت', en: 'hours'),
      RecurrenceUnit.day => LifeMateRuntimeLocale.select(fa: 'روز', en: 'days'),
      RecurrenceUnit.week =>
        LifeMateRuntimeLocale.select(fa: 'هفته', en: 'weeks'),
      RecurrenceUnit.month =>
        LifeMateRuntimeLocale.select(fa: 'ماه', en: 'months'),
      RecurrenceUnit.year =>
        LifeMateRuntimeLocale.select(fa: 'سال', en: 'years'),
    };
  }

  String get _preview {
    if (!_intervalMode) {
      return LifeMateRuntimeLocale.select(
        fa: 'زمان‌های مشخصی که پایین انتخاب می‌کنید اجرا می‌شوند.',
        en: 'Runs at the explicit times selected below.',
      );
    }
    final anchor = formatAppTime(context, _anchor);
    if (_unit == RecurrenceUnit.hour && _hourPresets.contains(_interval)) {
      return '$anchor · ${_presetLabel(_interval)}';
    }
    return LifeMateRuntimeLocale.select(
      fa: 'از $anchor، هر $_interval ${_unitLabel(_unit)} یک نوبت ساخته می‌شود.',
      en: 'Starting at $anchor, one occurrence is created every $_interval ${_unitLabel(_unit)}.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('medication.schedule.interval.title'),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final hours in _hourPresets)
              ChoiceChip(
                key: ValueKey('treatment-hour-preset-$hours'),
                label: Text(_presetLabel(hours)),
                selected: _intervalMode &&
                    _unit == RecurrenceUnit.hour &&
                    _interval == hours,
                onSelected:
                    !widget.enabled ? null : (_) => _selectHourPreset(hours),
              ),
            ChoiceChip(
              key: const ValueKey('treatment-schedule-custom-interval'),
              label: Text(context.tr('medication.schedule.interval.custom')),
              selected: _intervalMode &&
                  !(_unit == RecurrenceUnit.hour &&
                      _hourPresets.contains(_interval)),
              onSelected: !widget.enabled
                  ? null
                  : (_) {
                      setState(() {
                        _intervalMode = true;
                        if (_unit == RecurrenceUnit.hour &&
                            _hourPresets.contains(_interval)) {
                          _interval = 10;
                        }
                      });
                      _publish();
                    },
            ),
            ChoiceChip(
              key: const ValueKey('treatment-schedule-explicit'),
              label: Text(
                LifeMateRuntimeLocale.select(
                  fa: 'ساعت‌های مشخص',
                  en: 'Specific times',
                ),
              ),
              selected: !_intervalMode,
              onSelected: !widget.enabled
                  ? null
                  : (_) {
                      setState(() => _intervalMode = false);
                      _publish();
                    },
            ),
          ],
        ),
        if (_intervalMode) ...[
          const SizedBox(height: 14),
          if (!(_unit == RecurrenceUnit.hour &&
              _hourPresets.contains(_interval)))
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: WellMateLabeledField(
                    label: LifeMateRuntimeLocale.select(
                      fa: 'فاصله تکرار',
                      en: 'Repeat interval',
                    ),
                    icon: Icons.repeat_rounded,
                    child: TextFormField(
                      key: ValueKey(
                        'treatment-recurrence-interval-$_interval-${_unit.name}',
                      ),
                      initialValue: _interval.toString(),
                      keyboardType: TextInputType.number,
                      inputFormatters: const [
                        LifeMateLocaleDigitInputFormatter(),
                      ],
                      decoration: wellMateFieldDecoration(),
                      validator: (value) {
                        if (!_intervalMode) return null;
                        final parsed = int.tryParse(value?.trim() ?? '');
                        final max = _unit == RecurrenceUnit.hour ? 8760 : 365;
                        if (parsed == null || parsed < 1 || parsed > max) {
                          return LifeMateRuntimeLocale.select(
                            fa: 'عدد معتبر وارد کنید.',
                            en: 'Enter a valid interval.',
                          );
                        }
                        return null;
                      },
                      onChanged: (value) {
                        final parsed = int.tryParse(value.trim());
                        if (parsed == null || parsed < 1) return;
                        _interval = parsed;
                        _publish();
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: WellMateLabeledField(
                    label:
                        LifeMateRuntimeLocale.select(fa: 'واحد', en: 'Unit'),
                    icon: Icons.timelapse_rounded,
                    child: DropdownButtonFormField<RecurrenceUnit>(
                      key: const ValueKey('treatment-recurrence-unit'),
                      initialValue: _unit,
                      isExpanded: true,
                      decoration: wellMateFieldDecoration(),
                      items: [
                        for (final unit in RecurrenceUnit.values)
                          DropdownMenuItem(
                            value: unit,
                            child: Text(_unitLabel(unit)),
                          ),
                      ],
                      onChanged: !widget.enabled
                          ? null
                          : (value) {
                              if (value == null) return;
                              setState(() => _unit = value);
                              _publish();
                            },
                    ),
                  ),
                ),
              ],
            ),
          WellMateLabeledField(
            label: context.tr('medication.schedule.interval.firstDose'),
            icon: Icons.access_time_rounded,
            child: InkWell(
              key: const ValueKey('treatment-recurrence-anchor'),
              onTap: widget.enabled ? _pickAnchor : null,
              borderRadius: BorderRadius.circular(17),
              child: InputDecorator(
                decoration: wellMateFieldDecoration(),
                child: Text(
                  formatAppTime(context, _anchor),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.darkBlue,
                  ),
                ),
              ),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.verified_user_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.tr('medication.schedule.interval.exactNotice'),
                    style: const TextStyle(
                      height: 1.45,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            key: const ValueKey('medication-sleep-preferences'),
            onPressed: widget.enabled ? _openSleepPreferences : null,
            icon: const Icon(Icons.bedtime_outlined),
            label: Text(
              context.tr('medication.schedule.interval.sleepPreferences'),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('medication-nearby-optimization'),
            onPressed: widget.enabled ? _openNearbyOptimization : null,
            icon: const Icon(Icons.merge_type_rounded),
            label: Text(
              LifeMateRuntimeLocale.select(
                fa: 'یکپارچه‌سازی زمان‌های نزدیک',
                en: 'Combine nearby medication times',
              ),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('medication-sleep-optimization'),
            onPressed: widget.enabled ? _openSleepOptimization : null,
            icon: const Icon(Icons.bedtime_off_outlined),
            label: Text(
              LifeMateRuntimeLocale.select(
                fa: 'پیشنهاد زمان با ساعات خواب',
                en: 'Sleep-aware timing proposal',
              ),
            ),
          ),
        ],
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            _preview,
            key: const ValueKey('treatment-recurrence-preview'),
            style: const TextStyle(
              height: 1.45,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
