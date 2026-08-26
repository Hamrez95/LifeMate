import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';

import '../../core/theme/app_style.dart';
import '../../core/utils/persian_date_utils.dart';
import '../../core/widgets/labeled_form_field.dart';

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
  bool _intervalMode = false;
  RecurrenceUnit _unit = RecurrenceUnit.hour;
  int _interval = 6;
  late TimeOfDay _anchor;

  @override
  void initState() {
    super.initState();
    _anchor = widget.initialAnchor;
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

  String _unitLabel(RecurrenceUnit unit) {
    return switch (unit) {
      RecurrenceUnit.hour => LifeMateRuntimeLocale.select(
          fa: 'ساعت',
          en: 'hours',
        ),
      RecurrenceUnit.day => LifeMateRuntimeLocale.select(fa: 'روز', en: 'days'),
      RecurrenceUnit.week => LifeMateRuntimeLocale.select(
          fa: 'هفته',
          en: 'weeks',
        ),
      RecurrenceUnit.month => LifeMateRuntimeLocale.select(
          fa: 'ماه',
          en: 'months',
        ),
      RecurrenceUnit.year => LifeMateRuntimeLocale.select(
          fa: 'سال',
          en: 'years',
        ),
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
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
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
            ChoiceChip(
              key: const ValueKey('treatment-schedule-interval'),
              label: Text(
                LifeMateRuntimeLocale.select(
                  fa: 'هر X ساعت/روز/ماه',
                  en: 'Every X hours/days/months',
                ),
              ),
              selected: _intervalMode,
              onSelected: !widget.enabled
                  ? null
                  : (_) {
                      setState(() => _intervalMode = true);
                      _publish();
                    },
            ),
          ],
        ),
        if (_intervalMode) ...[
          const SizedBox(height: 14),
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
                    key: const ValueKey('treatment-recurrence-interval'),
                    initialValue: _interval.toString(),
                    keyboardType: TextInputType.number,
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
                  label: LifeMateRuntimeLocale.select(fa: 'واحد', en: 'Unit'),
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
            label: LifeMateRuntimeLocale.select(
              fa: 'شروع اولین نوبت',
              en: 'First occurrence time',
            ),
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
        ],
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            _preview,
            key: const ValueKey('treatment-recurrence-preview'),
            style: const TextStyle(height: 1.45, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
