import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';

import '../../core/theme/app_style.dart';
import '../../core/utils/persian_date_utils.dart';

const womenRose = Color(0xFFF05F8C);
const womenBlush = Color(0xFFFFEAF2);
const womenLilac = Color(0xFF9B6DD8);
const womenLavender = Color(0xFFF0E8FF);
const womenPeach = Color(0xFFF6B078);
const womenCream = Color(0xFFFFFBF7);
const womenInk = Color(0xFF29233D);

class WomenPhaseVisual {
  const WomenPhaseVisual({
    required this.label,
    required this.color,
    required this.icon,
    required this.message,
    required this.shortTip,
  });

  final String label;
  final Color color;
  final IconData icon;
  final String message;
  final String shortTip;
}

WomenPhaseVisual womenPhaseVisual(WomenCyclePhase? phase) {
  return switch (phase) {
    WomenCyclePhase.period => const WomenPhaseVisual(
      label: 'فاز قاعدگی',
      color: Color(0xFFF05F78),
      icon: Icons.water_drop_rounded,
      message:
          'ممکنه بدنت امروز آرامش، گرما و استراحت بیشتری بخواد. لازم نیست همه‌چیز را با سرعت همیشگی انجام بدی.',
      shortTip: 'استراحت، نوشیدنی گرم و توجه به دردهای غیرعادی',
    ),
    WomenCyclePhase.follicular => const WomenPhaseVisual(
      label: 'فاز فولیکولار',
      color: Color(0xFFB889E8),
      icon: Icons.auto_awesome_rounded,
      message:
          'در این بخش از چرخه ممکنه انرژی و تمرکزت کم‌کم بیشتر بشه. شروع آرام کارهای تازه می‌تونه حس خوبی بده.',
      shortTip: 'حرکت سبک، برنامه‌ریزی و خواب منظم',
    ),
    WomenCyclePhase.fertile => const WomenPhaseVisual(
      label: 'پنجره باروری تخمینی',
      color: Color(0xFF6F8DEB),
      icon: Icons.spa_rounded,
      message:
          'این بازه فقط یک تخمین تقویمی است. ممکنه سطح انرژی یا میل به ارتباط بیشتر شود، اما تجربه هر بدن متفاوت است.',
      shortTip: 'آب کافی، فعالیت متعادل و توجه به نشانه‌های بدنت',
    ),
    WomenCyclePhase.ovulation => const WomenPhaseVisual(
      label: 'روز تخمک‌گذاری تخمینی',
      color: Color(0xFF8B62D5),
      icon: Icons.local_florist_rounded,
      message:
          'امروز براساس طول چرخه، روز تخمک‌گذاری تخمین زده شده؛ این تخمین اثبات پزشکی تخمک‌گذاری نیست.',
      shortTip: 'فعالیت متعادل و ثبت نشانه‌های واقعی بدن',
    ),
    WomenCyclePhase.luteal => const WomenPhaseVisual(
      label: 'فاز لوتئال',
      color: Color(0xFFF3B35C),
      icon: Icons.wb_sunny_rounded,
      message:
          'ممکنه در روزهای پیش رو انرژی کمی آرام‌تر شود. کارها را خرد کن و برای استراحت کوتاه جا باز بگذار.',
      shortTip: 'غذای متعادل، خواب کافی و فشار کمتر',
    ),
    WomenCyclePhase.pms => const WomenPhaseVisual(
      label: 'PMS تخمینی',
      color: Color(0xFFE78374),
      icon: Icons.favorite_rounded,
      message:
          'اگر حساس‌تر، خسته‌تر یا کم‌حوصله‌تری، با خودت مهربان‌تر باش. احساس امروزت معتبر است و ممکنه فردا متفاوت باشد.',
      shortTip: 'کاهش فشار، آب کافی و گفت‌وگوی صادقانه',
    ),
    null => const WomenPhaseVisual(
      label: 'چرخه هنوز تنظیم نشده',
      color: womenLilac,
      icon: Icons.calendar_month_rounded,
      message:
          'با ثبت تاریخ آخرین دوره، تقویم شخصی و تخمین‌های چرخه آماده می‌شوند.',
      shortTip: 'اطلاعات پایه چرخه را در تنظیمات ثبت کن',
    ),
  };
}

List<WomenCycleRingSegment> womenCycleSegments(
  WomenCalendarEstimate? estimate,
) {
  if (estimate == null) {
    return const [
      WomenCycleRingSegment(color: womenRose, weight: 5),
      WomenCycleRingSegment(color: womenLilac, weight: 8),
      WomenCycleRingSegment(color: Color(0xFF6F8DEB), weight: 5),
      WomenCycleRingSegment(color: womenPeach, weight: 10),
    ];
  }
  final follicular = math.max(
    1,
    estimate.fertileWindowStartDay - estimate.periodLength - 1,
  );
  final fertile = math.max(
    1,
    estimate.fertileWindowEndDay - estimate.fertileWindowStartDay,
  );
  final luteal = math.max(
    1,
    estimate.pmsStartDay - estimate.fertileWindowEndDay - 1,
  );
  final pms = math.max(1, estimate.cycleLength - estimate.pmsStartDay + 1);
  return [
    WomenCycleRingSegment(
      color: const Color(0xFFF05F78),
      weight: estimate.periodLength.toDouble(),
    ),
    WomenCycleRingSegment(
      color: const Color(0xFFB889E8),
      weight: follicular.toDouble(),
    ),
    WomenCycleRingSegment(
      color: const Color(0xFF6F8DEB),
      weight: fertile.toDouble(),
    ),
    const WomenCycleRingSegment(color: Color(0xFF8B62D5), weight: 1),
    WomenCycleRingSegment(
      color: const Color(0xFFF3B35C),
      weight: luteal.toDouble(),
    ),
    WomenCycleRingSegment(
      color: const Color(0xFFE78374),
      weight: pms.toDouble(),
    ),
  ];
}

class WomenCycleBackground extends StatelessWidget {
  const WomenCycleBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [
                  Color(0xFFFFF8FB),
                  Color(0xFFF8F1FF),
                  Color(0xFFFFF8F3),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          top: -70,
          right: -50,
          child: _GlowOrb(color: womenRose.withValues(alpha: 0.13), size: 210),
        ),
        Positioned(
          top: 230,
          left: -90,
          child: _GlowOrb(color: womenLilac.withValues(alpha: 0.12), size: 250),
        ),
        Positioned(
          bottom: 120,
          right: -80,
          child: _GlowOrb(color: womenPeach.withValues(alpha: 0.10), size: 230),
        ),
        child,
      ],
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
      ),
    ),
  );
}

class WomenSoftCard extends StatelessWidget {
  const WomenSoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.gradient,
    this.color = Colors.white,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsets padding;
  final Gradient? gradient;
  final Color color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? color.withValues(alpha: 0.94) : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: borderColor ?? Colors.white.withValues(alpha: 0.78),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x102D1B44),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

class WomenSectionHeader extends StatelessWidget {
  const WomenSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: womenLavender,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, color: womenLilac, size: 21),
          ),
          const SizedBox(width: 11),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: womenInk,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11.5,
                    height: 1.5,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (actionLabel != null)
          TextButton(onPressed: onAction, child: Text(actionLabel!)),
      ],
    );
  }
}

class WomenPairHero extends StatelessWidget {
  const WomenPairHero({
    super.key,
    required this.apiClient,
    required this.ownerName,
    required this.companionName,
  });

  final LifeMateApiClient apiClient;
  final String ownerName;
  final String? companionName;

  @override
  Widget build(BuildContext context) {
    final hasCompanion = companionName?.trim().isNotEmpty == true;
    return WomenSoftCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      gradient: const LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [Color(0xFFFFEAF4), Color(0xFFF1E9FF)],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ownerName.isEmpty
                          ? 'سلام عزیزم 💗'
                          : 'سلام $ownerName جان 💗',
                      style: const TextStyle(
                        color: womenInk,
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      hasCompanion
                          ? '$companionName همدل توست؛ فقط خلاصه‌ای که خودت اجازه بدهی می‌بیند.'
                          : 'حال امروزت را ثبت کن؛ جزئیات خصوصی فقط برای خودت می‌ماند.',
                      style: const TextStyle(
                        color: Color(0xFF735E82),
                        fontSize: 11.5,
                        height: 1.55,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              LifeMateCurrentUserAvatar(apiClient: apiClient, radius: 24),
            ],
          ),
          if (hasCompanion) ...[
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                LifeMateCurrentUserAvatar(apiClient: apiClient, radius: 33),
                Transform.translate(
                  offset: const Offset(-8, 0),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.favorite_rounded,
                      color: womenRose,
                      size: 19,
                    ),
                  ),
                ),
                Transform.translate(
                  offset: const Offset(-16, 0),
                  child: CircleAvatar(
                    radius: 33,
                    backgroundColor: const Color(0xFFE9DEFF),
                    child: Text(
                      companionName!.trim().characters.first,
                      style: const TextStyle(
                        color: womenLilac,
                        fontSize: 25,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class WomenCycleHeroCard extends StatelessWidget {
  const WomenCycleHeroCard({
    super.key,
    required this.estimate,
    required this.onOpenCalendar,
  });

  final WomenCalendarEstimate? estimate;
  final VoidCallback onOpenCalendar;

  @override
  Widget build(BuildContext context) {
    final value = estimate;
    final visual = womenPhaseVisual(value?.detailedPhase);
    final progress = value == null
        ? 0.2
        : ((value.cycleDay - 1) / value.cycleLength).clamp(0.0, 1.0);
    return WomenSoftCard(
      key: const ValueKey('women-emotional-cycle-hero'),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 340;
          final ring = WomenCycleRing(
            segments: womenCycleSegments(value),
            progress: progress,
            size: compact ? 154 : 174,
            strokeWidth: compact ? 12 : 14,
            semanticsLabel: value == null
                ? 'چرخه تنظیم نشده'
                : 'روز ${value.cycleDay} از چرخه ${value.cycleLength} روزه',
            center: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value == null ? '—' : localizeDigits(context, value.cycleDay),
                  style: TextStyle(
                    color: visual.color,
                    fontSize: compact ? 27 : 31,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value == null
                      ? 'روز چرخه'
                      : 'از ${localizeDigits(context, value.cycleLength)} روز',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          );
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: visual.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(visual.icon, color: visual.color, size: 20),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      visual.label,
                      style: const TextStyle(
                        color: womenInk,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              if (value != null) ...[
                const SizedBox(height: 12),
                _CycleMetric(
                  icon: Icons.water_drop_outlined,
                  color: womenRose,
                  label:
                      '${localizeDigits(context, value.daysUntilNextPeriod)} روز تا دوره بعدی',
                ),
                const SizedBox(height: 8),
                _CycleMetric(
                  icon: Icons.local_florist_outlined,
                  color: womenLilac,
                  label:
                      '${localizeDigits(context, math.max(0, value.ovulationDay - value.cycleDay))} روز تا تخمک‌گذاری تخمینی',
                ),
              ],
              const SizedBox(height: 13),
              OutlinedButton.icon(
                onPressed: onOpenCalendar,
                icon: const Icon(Icons.calendar_month_rounded, size: 18),
                label: const Text('تقویم چرخه'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: womenRose,
                  side: const BorderSide(color: Color(0xFFF2A9C0)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ],
          );
          if (compact) {
            return Column(
              children: [ring, const SizedBox(height: 18), details],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ring,
              const SizedBox(width: 18),
              Expanded(child: details),
            ],
          );
        },
      ),
    );
  }
}

class _CycleMetric extends StatelessWidget {
  const _CycleMetric({
    required this.icon,
    required this.color,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 17, color: color),
      const SizedBox(width: 7),
      Expanded(
        child: Text(
          label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11.5,
          ),
        ),
      ),
    ],
  );
}

class MoodDefinition {
  const MoodDefinition(this.value, this.label, this.emoji, this.color);
  final String value;
  final String label;
  final String emoji;
  final Color color;
}

const womenMoods = <MoodDefinition>[
  MoodDefinition('great', 'عالی', '😄', Color(0xFF61C7A0)),
  MoodDefinition('good', 'خوب', '🙂', Color(0xFF88B7EE)),
  MoodDefinition('neutral', 'معمولی', '😐', Color(0xFFF0C36B)),
  MoodDefinition('low', 'کم‌حوصله', '😔', Color(0xFFF0A06B)),
  MoodDefinition('overwhelmed', 'تحت فشار', '😣', Color(0xFFE5767F)),
];

class SymptomDefinition {
  const SymptomDefinition(this.value, this.label, this.icon, this.color);
  final String value;
  final String label;
  final IconData icon;
  final Color color;
}

const womenSymptoms = <SymptomDefinition>[
  SymptomDefinition('cramps', 'درد شکم', Icons.bolt_rounded, Color(0xFFF06B8B)),
  SymptomDefinition(
    'headache',
    'سردرد',
    Icons.psychology_alt_rounded,
    Color(0xFF9A78D2),
  ),
  SymptomDefinition(
    'bloating',
    'نفخ',
    Icons.bubble_chart_rounded,
    Color(0xFFF2B15D),
  ),
  SymptomDefinition(
    'fatigue',
    'خستگی',
    Icons.bedtime_rounded,
    Color(0xFF7B77D2),
  ),
  SymptomDefinition(
    'breast_tenderness',
    'حساسیت سینه',
    Icons.favorite_outline_rounded,
    Color(0xFFE87BA6),
  ),
  SymptomDefinition(
    'back_pain',
    'کمردرد',
    Icons.accessibility_new_rounded,
    Color(0xFF7AA8D9),
  ),
  SymptomDefinition(
    'sleep_change',
    'تغییر خواب',
    Icons.nights_stay_rounded,
    Color(0xFF836FC5),
  ),
  SymptomDefinition(
    'appetite_change',
    'تغییر اشتها',
    Icons.restaurant_rounded,
    Color(0xFFDB9A57),
  ),
];

class SupportNeedDefinition {
  const SupportNeedDefinition(this.value, this.label, this.icon);
  final String value;
  final String label;
  final IconData icon;
}

const womenSupportNeeds = <SupportNeedDefinition>[
  SupportNeedDefinition(
    'none',
    'فعلاً خوبم',
    Icons.check_circle_outline_rounded,
  ),
  SupportNeedDefinition('rest', 'استراحت', Icons.bedtime_outlined),
  SupportNeedDefinition('talk', 'گفت‌وگو', Icons.chat_bubble_outline_rounded),
  SupportNeedDefinition('space', 'کمی خلوت', Icons.self_improvement_rounded),
  SupportNeedDefinition('warmth', 'نوشیدنی گرم', Icons.local_cafe_outlined),
  SupportNeedDefinition('walk', 'پیاده‌روی', Icons.directions_walk_rounded),
  SupportNeedDefinition('hug', 'آغوش', Icons.favorite_border_rounded),
];

class WomenDailyCheckInCard extends StatelessWidget {
  const WomenDailyCheckInCard({
    super.key,
    required this.mood,
    required this.energy,
    required this.symptoms,
    required this.supportNeed,
    required this.noteController,
    required this.shareSummary,
    required this.saving,
    required this.onMoodChanged,
    required this.onEnergyChanged,
    required this.onSymptomChanged,
    required this.onSupportNeedChanged,
    required this.onShareChanged,
    required this.onSave,
  });

  final String mood;
  final int energy;
  final Set<String> symptoms;
  final String supportNeed;
  final TextEditingController noteController;
  final bool shareSummary;
  final bool saving;
  final ValueChanged<String> onMoodChanged;
  final ValueChanged<int> onEnergyChanged;
  final void Function(String value, bool selected) onSymptomChanged;
  final ValueChanged<String> onSupportNeedChanged;
  final ValueChanged<bool> onShareChanged;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return WomenSoftCard(
      key: const ValueKey('women-daily-check-in-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const WomenSectionHeader(
            title: 'حس و حال امروز من',
            subtitle:
                'هر چیزی را که دوست داری ثبت کن؛ یادداشت و علائم خصوصی می‌مانند.',
            icon: Icons.emoji_emotions_outlined,
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 88,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: womenMoods.length,
              separatorBuilder: (_, __) => const SizedBox(width: 9),
              itemBuilder: (context, index) {
                final item = womenMoods[index];
                final selected = mood == item.value;
                return Semantics(
                  selected: selected,
                  button: true,
                  label: item.label,
                  child: InkWell(
                    onTap: () => onMoodChanged(item.value),
                    borderRadius: BorderRadius.circular(19),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 67,
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: selected
                            ? item.color.withValues(alpha: 0.18)
                            : const Color(0xFFFAF7FB),
                        borderRadius: BorderRadius.circular(19),
                        border: Border.all(
                          color: selected
                              ? item.color
                              : const Color(0xFFF1EBF4),
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            item.emoji,
                            style: const TextStyle(fontSize: 25),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            item.label,
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: selected ? item.color : womenInk,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text(
                'انرژی امروز',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              const Spacer(),
              Text(
                switch (energy) {
                  1 => 'خیلی کم',
                  2 => 'کم',
                  3 => 'متوسط',
                  4 => 'خوب',
                  _ => 'بالا',
                },
                style: const TextStyle(
                  color: womenLilac,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          Slider(
            value: energy.toDouble(),
            min: 1,
            max: 5,
            divisions: 4,
            activeColor: womenLilac,
            inactiveColor: womenLavender,
            onChanged: (value) => onEnergyChanged(value.round()),
          ),
          const SizedBox(height: 8),
          const Text(
            'علائم و نشانه‌ها',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: womenSymptoms
                .map((item) {
                  final selected = symptoms.contains(item.value);
                  return FilterChip(
                    selected: selected,
                    onSelected: (value) => onSymptomChanged(item.value, value),
                    avatar: Icon(
                      item.icon,
                      size: 17,
                      color: selected ? item.color : AppColors.textSecondary,
                    ),
                    label: Text(item.label),
                    selectedColor: item.color.withValues(alpha: 0.13),
                    backgroundColor: const Color(0xFFFAF8FB),
                    side: BorderSide(
                      color: selected
                          ? item.color.withValues(alpha: 0.55)
                          : const Color(0xFFF0ECF2),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  );
                })
                .toList(growable: false),
          ),
          const SizedBox(height: 16),
          const Text(
            'امروز بیشتر به چی نیاز داری؟',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: womenSupportNeeds
                .map((item) {
                  final selected = supportNeed == item.value;
                  return ChoiceChip(
                    selected: selected,
                    onSelected: (_) => onSupportNeedChanged(item.value),
                    avatar: Icon(
                      item.icon,
                      size: 17,
                      color: selected ? womenRose : AppColors.textSecondary,
                    ),
                    label: Text(item.label),
                    selectedColor: womenBlush,
                    backgroundColor: const Color(0xFFFAF8FB),
                    side: BorderSide(
                      color: selected
                          ? womenRose.withValues(alpha: 0.45)
                          : const Color(0xFFF0ECF2),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  );
                })
                .toList(growable: false),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: noteController,
            maxLength: 500,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'یادداشت خصوصی امروز',
              hintText: 'حست، خوابت یا اتفاق مهم امروز را بنویس…',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              filled: true,
              fillColor: const Color(0xFFFBF8FC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: shareSummary,
            onChanged: onShareChanged,
            activeTrackColor: womenRose.withValues(alpha: 0.5),
            title: const Text(
              'اشتراک خلاصه با همدل',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: const Text(
              'فقط حال کلی، انرژی و نیاز حمایتی نمایش داده می‌شود؛ علائم و یادداشت خصوصی نیستند.',
              style: TextStyle(fontSize: 10.5, height: 1.5),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: saving ? null : onSave,
              icon: saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.favorite_rounded),
              label: Text(saving ? 'در حال ذخیره…' : 'ثبت حال امروز'),
              style: FilledButton.styleFrom(
                backgroundColor: womenRose,
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

class WomenGuidanceCard extends StatelessWidget {
  const WomenGuidanceCard({super.key, required this.phase});

  final WomenCyclePhase? phase;

  @override
  Widget build(BuildContext context) {
    final visual = womenPhaseVisual(phase);
    return WomenSoftCard(
      gradient: LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [visual.color.withValues(alpha: 0.16), const Color(0xFFFFF9FC)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WomenSectionHeader(
            title: 'نکته امروز',
            subtitle: visual.label,
            icon: Icons.local_florist_rounded,
          ),
          const SizedBox(height: 13),
          Text(
            visual.message,
            style: const TextStyle(
              color: Color(0xFF5B4B66),
              height: 1.75,
              fontSize: 12.5,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(17),
            ),
            child: Row(
              children: [
                Icon(Icons.eco_outlined, color: visual.color, size: 20),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    visual.shortTip,
                    style: TextStyle(
                      color: visual.color,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class WomenTimelineCard extends StatefulWidget {
  const WomenTimelineCard({super.key, required this.estimate});

  final WomenCalendarEstimate? estimate;

  @override
  State<WomenTimelineCard> createState() => _WomenTimelineCardState();
}

class _WomenTimelineCardState extends State<WomenTimelineCard> {
  int selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final selectedDate = DateTime(
      today.year,
      today.month,
      today.day,
    ).add(Duration(days: selectedIndex));
    final phase = widget.estimate?.phaseForDate(selectedDate);
    final visual = womenPhaseVisual(phase);
    return WomenSoftCard(
      key: const ValueKey('women-emotional-14-day-timeline'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const WomenSectionHeader(
            title: '۱۴ روز آینده',
            subtitle:
                'هر روز را لمس کن تا فاز تخمینی و پیشنهاد ملایم همان روز را ببینی.',
            icon: Icons.timeline_rounded,
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 119,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 14,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final date = DateTime(
                  today.year,
                  today.month,
                  today.day,
                ).add(Duration(days: index));
                final dayPhase = widget.estimate?.phaseForDate(date);
                final dayVisual = womenPhaseVisual(dayPhase);
                final selected = index == selectedIndex;
                return InkWell(
                  onTap: () => setState(() => selectedIndex = index),
                  borderRadius: BorderRadius.circular(18),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 72,
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: selected
                          ? dayVisual.color.withValues(alpha: 0.17)
                          : const Color(0xFFFAF8FB),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: selected
                            ? dayVisual.color
                            : const Color(0xFFF0ECF2),
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          index == 0 ? 'امروز' : localizeDigits(context, index),
                          style: TextStyle(
                            fontSize: index == 0 ? 10 : 14,
                            fontWeight: FontWeight.w900,
                            color: selected ? dayVisual.color : womenInk,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Icon(dayVisual.icon, size: 22, color: dayVisual.color),
                        const SizedBox(height: 6),
                        Text(
                          formatAppDate(context, date, includeWeekday: false),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 8.5),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: double.infinity,
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: visual.color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(visual.icon, color: visual.color),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        visual.label,
                        style: TextStyle(
                          color: visual.color,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        visual.shortTip,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          height: 1.5,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class WomenReportsCard extends StatelessWidget {
  const WomenReportsCard({
    super.key,
    required this.episodes,
    required this.currentSymptoms,
  });

  final List<Map<String, dynamic>> episodes;
  final Set<String> currentSymptoms;

  @override
  Widget build(BuildContext context) {
    final sorted =
        episodes
            .map(
              (item) => DateTime.tryParse(item['startedOn']?.toString() ?? ''),
            )
            .whereType<DateTime>()
            .toList()
          ..sort();
    final cycleIntervals = <int>[];
    for (var index = 1; index < sorted.length; index++) {
      cycleIntervals.add(sorted[index].difference(sorted[index - 1]).inDays);
    }
    final finishedLengths = episodes
        .map((item) {
          final start = DateTime.tryParse(item['startedOn']?.toString() ?? '');
          final end = DateTime.tryParse(item['endedOn']?.toString() ?? '');
          if (start == null || end == null) return null;
          return end.difference(start).inDays + 1;
        })
        .whereType<int>()
        .toList();
    final avgCycle = cycleIntervals.isEmpty
        ? null
        : cycleIntervals.reduce((a, b) => a + b) / cycleIntervals.length;
    final avgPeriod = finishedLengths.isEmpty
        ? null
        : finishedLengths.reduce((a, b) => a + b) / finishedLengths.length;
    final variation = cycleIntervals.length < 2
        ? null
        : cycleIntervals.reduce(math.max) - cycleIntervals.reduce(math.min);
    final regularity = variation == null
        ? 'داده بیشتر لازم است'
        : variation <= 7
        ? 'نسبتاً منظم'
        : 'متغیر';

    return WomenSoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const WomenSectionHeader(
            title: 'گزارش‌های من',
            subtitle: 'خلاصه‌ای ساده از ثبت‌های واقعی؛ بدون تشخیص پزشکی.',
            icon: Icons.insights_rounded,
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth < 330
                  ? constraints.maxWidth
                  : (constraints.maxWidth - 10) / 2;
              final cards = [
                _ReportMetric(
                  title: 'دوره‌های ثبت‌شده',
                  value: localizeDigits(context, episodes.length),
                  icon: Icons.calendar_month_rounded,
                  color: womenRose,
                ),
                _ReportMetric(
                  title: 'میانگین طول چرخه',
                  value: avgCycle == null
                      ? '—'
                      : '${localizeDigits(context, avgCycle.round())} روز',
                  icon: Icons.loop_rounded,
                  color: womenLilac,
                ),
                _ReportMetric(
                  title: 'میانگین خون‌ریزی',
                  value: avgPeriod == null
                      ? '—'
                      : '${localizeDigits(context, avgPeriod.round())} روز',
                  icon: Icons.water_drop_outlined,
                  color: womenRose,
                ),
                _ReportMetric(
                  title: 'الگوی چرخه',
                  value: regularity,
                  icon: Icons.show_chart_rounded,
                  color: womenPeach,
                ),
                _ReportMetric(
                  title: 'علائم ثبت‌شده امروز',
                  value: localizeDigits(context, currentSymptoms.length),
                  icon: Icons.health_and_safety_outlined,
                  color: const Color(0xFF6F8DEB),
                ),
              ];
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: cards
                    .map((card) => SizedBox(width: width, child: card))
                    .toList(growable: false),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ReportMetric extends StatelessWidget {
  const _ReportMetric({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: color.withValues(alpha: 0.14)),
    ),
    child: Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: womenInk,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 9.5,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class WomenRemindersCard extends StatelessWidget {
  const WomenRemindersCard({
    super.key,
    required this.estimate,
    required this.remindersEnabled,
    required this.activeTreatmentCount,
  });

  final WomenCalendarEstimate? estimate;
  final bool remindersEnabled;
  final int activeTreatmentCount;

  @override
  Widget build(BuildContext context) {
    return WomenSoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const WomenSectionHeader(
            title: 'یادآوری‌ها',
            subtitle: 'چرخه و برنامه درمانی در یک نگاه',
            icon: Icons.notifications_active_outlined,
          ),
          const SizedBox(height: 12),
          _ReminderRow(
            icon: Icons.water_drop_outlined,
            color: womenRose,
            title: 'نزدیک‌شدن دوره',
            value: !remindersEnabled
                ? 'خاموش'
                : estimate == null
                ? 'پس از تنظیم چرخه فعال می‌شود'
                : '${localizeDigits(context, estimate.daysUntilNextPeriod)} روز دیگر',
          ),
          const SizedBox(height: 9),
          _ReminderRow(
            icon: Icons.medication_outlined,
            color: womenLilac,
            title: 'برنامه‌های درمانی فعال',
            value: '${localizeDigits(context, activeTreatmentCount)} برنامه',
          ),
        ],
      ),
    );
  }
}

class _ReminderRow extends StatelessWidget {
  const _ReminderRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        Text(
          value,
          style: TextStyle(color: color, fontWeight: FontWeight.w900),
        ),
      ],
    ),
  );
}

class WomenPrivacyNotice extends StatelessWidget {
  const WomenPrivacyNotice({super.key});

  @override
  Widget build(BuildContext context) => WomenSoftCard(
    color: const Color(0xFFFFF8E9),
    borderColor: const Color(0xFFF4DEAC),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.shield_outlined, color: Color(0xFF9B6D1A)),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'تاریخ‌ها و فازها تخمینی‌اند و جایگزین نظر پزشک نیستند. این بخش برای تشخیص، اثبات تخمک‌گذاری یا پیشگیری از بارداری استفاده نمی‌شود. علائم و یادداشت خصوصی به CareMate ارسال نمی‌شوند.',
            style: TextStyle(
              color: Color(0xFF745A25),
              fontSize: 10.5,
              height: 1.7,
            ),
          ),
        ),
      ],
    ),
  );
}
