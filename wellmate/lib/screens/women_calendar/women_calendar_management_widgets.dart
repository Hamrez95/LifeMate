import 'package:flutter/material.dart';

import '../../core/theme/app_style.dart';
import '../../core/utils/persian_date_utils.dart';
import 'women_calendar_experience_widgets.dart';

class WomenCycleSettingsCard extends StatelessWidget {
  const WomenCycleSettingsCard({
    super.key,
    required this.lastPeriodStart,
    required this.cycleLength,
    required this.periodLength,
    required this.remindersEnabled,
    required this.saving,
    required this.onPickDate,
    required this.onCycleChanged,
    required this.onPeriodChanged,
    required this.onReminderChanged,
    required this.onSave,
  });

  final DateTime? lastPeriodStart;
  final int cycleLength;
  final int periodLength;
  final bool remindersEnabled;
  final bool saving;
  final VoidCallback onPickDate;
  final ValueChanged<int> onCycleChanged;
  final ValueChanged<int> onPeriodChanged;
  final ValueChanged<bool> onReminderChanged;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return WomenSoftCard(
      key: const ValueKey('women-calendar-settings-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const WomenSectionHeader(
            title: 'تنظیمات چرخه',
            subtitle: 'اطلاعات پایه برای تخمین تقویم و یادآوری خصوصی',
            icon: Icons.tune_rounded,
          ),
          const SizedBox(height: 16),
          _SettingsTile(
            key: const ValueKey('women-calendar-last-period-picker'),
            label: 'شروع آخرین دوره',
            value: lastPeriodStart == null
                ? 'انتخاب تاریخ'
                : formatAppDate(context, lastPeriodStart!),
            icon: Icons.event_rounded,
            color: womenRose,
            onTap: onPickDate,
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 330;
              final cycle = _NumberSetting(
                title: 'طول معمول چرخه',
                value: cycleLength,
                min: 21,
                max: 45,
                suffix: 'روز',
                color: womenLilac,
                onChanged: onCycleChanged,
              );
              final period = _NumberSetting(
                title: 'طول معمول خون‌ریزی',
                value: periodLength,
                min: 1,
                max: 10,
                suffix: 'روز',
                color: womenRose,
                onChanged: onPeriodChanged,
              );
              if (compact) {
                return Column(
                  children: [cycle, const SizedBox(height: 10), period],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: cycle),
                  const SizedBox(width: 10),
                  Expanded(child: period),
                ],
              );
            },
          ),
          const SizedBox(height: 13),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8FC),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFF2E8F0)),
            ),
            child: SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: remindersEnabled,
              onChanged: onReminderChanged,
              activeTrackColor: womenRose.withValues(alpha: 0.5),
              title: const Text(
                'یادآوری نزدیک‌شدن دوره',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: const Text(
                'متن اعلان بدون نمایش جزئیات حساس ارسال می‌شود.',
                style: TextStyle(fontSize: 10.5, height: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: saving || lastPeriodStart == null ? null : onSave,
              icon: saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_rounded),
              label: Text(saving ? 'در حال ذخیره…' : 'ذخیره تنظیمات'),
              style: FilledButton.styleFrom(
                backgroundColor: womenLilac,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: color.withValues(alpha: 0.07),
    borderRadius: BorderRadius.circular(19),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(19),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 43,
              height: 43,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 10.5,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    style: const TextStyle(
                      color: womenInk,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.edit_calendar_rounded, color: color, size: 21),
          ],
        ),
      ),
    ),
  );
}

class _NumberSetting extends StatelessWidget {
  const _NumberSetting({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.suffix,
    required this.color,
    required this.onChanged,
  });

  final String title;
  final int value;
  final int min;
  final int max;
  final String suffix;
  final Color color;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(19),
      border: Border.all(color: color.withValues(alpha: 0.12)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 2,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 10.5,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _StepButton(
              icon: Icons.remove_rounded,
              enabled: value > min,
              color: color,
              onTap: () => onChanged(value - 1),
            ),
            Expanded(
              child: Text(
                '${localizeDigits(context, value)} $suffix',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: womenInk,
                ),
              ),
            ),
            _StepButton(
              icon: Icons.add_rounded,
              enabled: value < max,
              color: color,
              onTap: () => onChanged(value + 1),
            ),
          ],
        ),
      ],
    ),
  );
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.enabled,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton.filledTonal(
    onPressed: enabled ? onTap : null,
    icon: Icon(icon, size: 18),
    style: IconButton.styleFrom(
      foregroundColor: color,
      backgroundColor: Colors.white,
      disabledForegroundColor: Colors.grey.shade300,
      minimumSize: const Size(38, 38),
      maximumSize: const Size(38, 38),
    ),
  );
}

class WomenPeriodHistoryCard extends StatelessWidget {
  const WomenPeriodHistoryCard({
    super.key,
    required this.episodes,
    required this.hasOpenEpisode,
    required this.saving,
    required this.onStart,
    required this.onFinish,
    required this.onEdit,
  });

  final List<Map<String, dynamic>> episodes;
  final bool hasOpenEpisode;
  final bool saving;
  final VoidCallback onStart;
  final VoidCallback onFinish;
  final ValueChanged<Map<String, dynamic>> onEdit;

  @override
  Widget build(BuildContext context) {
    return WomenSoftCard(
      key: const ValueKey('women-period-history-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const WomenSectionHeader(
            title: 'ثبت دوره و یادداشت',
            subtitle: 'تاریخ واقعی دوره‌ها را ثبت کن تا گزارش‌ها دقیق‌تر شوند.',
            icon: Icons.edit_note_rounded,
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: saving ? null : (hasOpenEpisode ? onFinish : onStart),
              icon: Icon(
                hasOpenEpisode
                    ? Icons.stop_circle_outlined
                    : Icons.play_circle_outline_rounded,
              ),
              label: Text(
                hasOpenEpisode ? 'ثبت پایان دوره برای امروز' : 'شروع دوره جدید',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: womenRose,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(17),
                ),
              ),
            ),
          ),
          if (episodes.isNotEmpty) ...[
            const SizedBox(height: 15),
            const Text(
              'ثبت‌های اخیر',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 9),
            ...episodes.take(4).map(
              (episode) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: const Color(0xFFFFF8FB),
                  borderRadius: BorderRadius.circular(17),
                  child: InkWell(
                    onTap: saving ? null : () => onEdit(episode),
                    borderRadius: BorderRadius.circular(17),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: womenBlush,
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: const Icon(
                              Icons.water_drop_rounded,
                              color: womenRose,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  formatAppDate(
                                    context,
                                    DateTime.parse(episode['startedOn'].toString()),
                                  ),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                Text(
                                  episode['endedOn'] == null
                                      ? 'در حال ادامه'
                                      : 'تا ${formatAppDate(context, DateTime.parse(episode['endedOn'].toString()))}',
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.edit_outlined,
                            color: womenLilac,
                            size: 19,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
