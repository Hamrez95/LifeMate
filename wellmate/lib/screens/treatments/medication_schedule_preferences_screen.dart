import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:lifemate_ui/lifemate_ui.dart';

import '../../core/theme/app_style.dart';
import 'medication_plan_timing_screen.dart';

class MedicationSchedulePreferencesScreen extends StatefulWidget {
  const MedicationSchedulePreferencesScreen({super.key, this.api});

  final LifeMateMedicationScheduleApi? api;

  @override
  State<MedicationSchedulePreferencesScreen> createState() =>
      _MedicationSchedulePreferencesScreenState();
}

class _MedicationSchedulePreferencesScreenState
    extends State<MedicationSchedulePreferencesScreen> {
  late final LifeMateMedicationScheduleApi _api =
      widget.api ?? LifeMateMedicationScheduleApi.fromEnvironment();
  LifeMateMedicationSchedulePreferences? _current;
  List<LifeMateMedicationSchedulePlan> _plans = const [];
  bool _enabled = false;
  TimeOfDay _start = const TimeOfDay(hour: 23, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 7, minute: 0);
  bool _loading = true;
  bool _saving = false;
  String? _error;

  bool get _fa => Localizations.localeOf(context).languageCode == 'fa';
  String _copy(String fa, String en) => _fa ? fa : en;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    if (widget.api == null) _api.close();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait<Object>([
        _api.getPreferences(),
        _api.listPlans(),
      ]);
      final value = results[0] as LifeMateMedicationSchedulePreferences;
      final plans = results[1] as List<LifeMateMedicationSchedulePlan>;
      if (!mounted) return;
      setState(() {
        _current = value;
        _plans = plans;
        _enabled = value.sleepWindowEnabled;
        _start = _parseTime(value.sleepStartLocalTime) ?? _start;
        _end = _parseTime(value.sleepEndLocalTime) ?? _end;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = context.tr('medication.schedule.preferences.loadFailed');
      });
    }
  }

  Future<void> _reloadPlans() async {
    try {
      final plans = await _api.listPlans();
      if (mounted) setState(() => _plans = plans);
    } catch (_) {
      // Keep the currently visible snapshot; a full retry remains available.
    }
  }

  Future<void> _pickStart() async {
    final value = await showTimePicker(context: context, initialTime: _start);
    if (value != null && mounted) setState(() => _start = value);
  }

  Future<void> _pickEnd() async {
    final value = await showTimePicker(context: context, initialTime: _end);
    if (value != null && mounted) setState(() => _end = value);
  }

  Future<void> _save() async {
    final current = _current;
    if (current == null || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final value = await _api.savePreferences(
        current: current,
        timeZone: current.timeZone,
        sleepWindowEnabled: _enabled,
        sleepStartLocalTime: _formatTime(_start),
        sleepEndLocalTime: _formatTime(_end),
      );
      if (!mounted) return;
      setState(() {
        _current = value;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('medication.schedule.preferences.saved')),
        ),
      );
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      if (error.statusCode == 409) {
        setState(() => _saving = false);
        await _load();
        if (!mounted) return;
        setState(
          () => _error =
              context.tr('medication.schedule.preferences.stale'),
        );
        return;
      }
      setState(() {
        _saving = false;
        _error = context.tr('medication.schedule.preferences.saveFailed');
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = context.tr('medication.schedule.preferences.saveFailed');
      });
    }
  }

  Future<void> _openPlan(LifeMateMedicationSchedulePlan plan) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => MedicationPlanTimingScreen(plan: plan, api: _api),
      ),
    );
    if (mounted) await _reloadPlans();
  }

  String _planSummary(LifeMateMedicationSchedulePlan plan) {
    final recurrence = plan.recurrence;
    final anchor = plan.recurrenceStartLocalTime;
    if (recurrence == null) {
      return _copy('برنامه با ساعت‌های مشخص', 'Specific-time schedule');
    }
    final unit = recurrence['unit']?.toString();
    final interval = int.tryParse(recurrence['interval']?.toString() ?? '');
    if (unit == 'hour' && interval != null) {
      final intervalText = switch (interval) {
        24 => _copy('روزانه · هر ۲۴ ساعت', 'Daily · every 24 hours'),
        48 => _copy('هر ۲ روز · ۴۸ ساعت', 'Every 2 days · 48 hours'),
        _ => _copy('هر $interval ساعت', 'Every $interval hours'),
      };
      return anchor == null ? intervalText : '$intervalText · $anchor';
    }
    return _copy('برنامه تکرارشونده', 'Recurring schedule');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(context.tr('medication.schedule.preferences.title')),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _current == null
                ? _errorState()
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SwitchListTile.adaptive(
                              contentPadding: EdgeInsets.zero,
                              value: _enabled,
                              onChanged: _saving
                                  ? null
                                  : (value) =>
                                      setState(() => _enabled = value),
                              title: Text(
                                context.tr(
                                  'medication.schedule.preferences.sleepWindow',
                                ),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              subtitle: Text(
                                context.tr(
                                  'medication.schedule.preferences.explanation',
                                ),
                              ),
                            ),
                            if (_enabled) ...[
                              const SizedBox(height: 12),
                              _TimeTile(
                                label: context.tr(
                                  'medication.schedule.preferences.sleepStart',
                                ),
                                value: _start.format(context),
                                onTap: _saving ? null : _pickStart,
                              ),
                              const SizedBox(height: 10),
                              _TimeTile(
                                label: context.tr(
                                  'medication.schedule.preferences.sleepEnd',
                                ),
                                value: _end.format(context),
                                onTap: _saving ? null : _pickEnd,
                              ),
                            ],
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                const Icon(Icons.public_rounded, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '${context.tr('medication.schedule.preferences.timeZone')}: ${_current!.timeZone}',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save_rounded),
                        label: Text(context.tr('common.save')),
                      ),
                      const SizedBox(height: 28),
                      Text(
                        _copy(
                          'قواعد زمان‌بندی هر دارو',
                          'Medication timing rules',
                        ),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: AppColors.darkBlue,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _copy(
                          'در این بخش فقط محدودیت‌هایی را ثبت می‌کنی که خودت می‌دانی. LifeMate تداخل دارویی یا ایمنی پزشکی را بررسی نمی‌کند.',
                          'Only record timing constraints you already know. LifeMate does not check drug interactions or medical safety.',
                        ),
                        style: const TextStyle(height: 1.45),
                      ),
                      const SizedBox(height: 12),
                      if (_plans.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _copy(
                              'فعلاً داروی فعالی برای تنظیم زمان‌بندی نداری.',
                              'There are no active medications to configure yet.',
                            ),
                          ),
                        )
                      else
                        for (final plan in _plans) ...[
                          _PlanTimingTile(
                            plan: plan,
                            summary: _planSummary(plan),
                            onTap: () => _openPlan(plan),
                            lockedLabel: _copy('زمان ثابت', 'Fixed timing'),
                            groupingLabel: _copy(
                              'پیشنهاد زمان نزدیک مجاز',
                              'Nearby proposals allowed',
                            ),
                            spacingLabel: _copy(
                              'دستور فاصله ثبت شده',
                              'Spacing instruction saved',
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                    ],
                  ),
      ),
    );
  }

  Widget _errorState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error ??
                    context.tr('medication.schedule.preferences.loadFailed'),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _load,
                child: Text(context.tr('common.retry')),
              ),
            ],
          ),
        ),
      );

  static TimeOfDay? _parseTime(String? value) {
    if (value == null) return null;
    final parts = value.split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null || hour > 23 || minute > 59) {
      return null;
    }
    return TimeOfDay(hour: hour, minute: minute);
  }

  static String _formatTime(TimeOfDay value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}

class _PlanTimingTile extends StatelessWidget {
  const _PlanTimingTile({
    required this.plan,
    required this.summary,
    required this.onTap,
    required this.lockedLabel,
    required this.groupingLabel,
    required this.spacingLabel,
  });

  final LifeMateMedicationSchedulePlan plan;
  final String summary;
  final VoidCallback onTap;
  final String lockedLabel;
  final String groupingLabel;
  final String spacingLabel;

  @override
  Widget build(BuildContext context) {
    final timing = plan.timing;
    final hasSpacing = timing.manualSpacingBeforeMinutes > 0 ||
        timing.manualSpacingAfterMinutes > 0 ||
        (timing.timingNote?.isNotEmpty ?? false);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const CircleAvatar(
                backgroundColor: Color(0xFFF1F5F9),
                child: Icon(Icons.medication_outlined),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plan.medicationName,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 3),
                    Text(summary),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (timing.timingLocked)
                          _StatusChip(
                            icon: Icons.lock_clock_outlined,
                            label: lockedLabel,
                          ),
                        if (timing.nearbyGroupingEnabled)
                          _StatusChip(
                            icon: Icons.merge_type_rounded,
                            label: groupingLabel,
                          ),
                        if (hasSpacing)
                          _StatusChip(
                            icon: Icons.rule_rounded,
                            label: spacingLabel,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
}

class _TimeTile extends StatelessWidget {
  const _TimeTile({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            const Icon(Icons.bedtime_outlined),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }
}
