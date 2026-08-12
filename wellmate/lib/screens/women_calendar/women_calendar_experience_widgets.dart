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
    WomenCyclePhase.period => WomenPhaseVisual(
      label: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'فاز قاعدگی',
          en: "Menstrual phase",
        ),
        en: "Menstrual phase",
      ),
      color: Color(0xFFF05F78),
      icon: Icons.water_drop_rounded,
      message: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'ممکنه بدنت امروز آرامش، گرما و استراحت بیشتری بخواد. لازم نیست همه‌چیز را با سرعت همیشگی انجام بدی.',
          en: "Your body may need more peace, warmth and rest today. You don't have to do everything at the usual speed.",
        ),
        en: "Your body may need more peace, warmth and rest today. You don't have to do everything at the usual speed.",
      ),
      shortTip: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'استراحت، نوشیدنی گرم و توجه به دردهای غیرعادی',
          en: "Rest, warm drinks and pay attention to unusual pains",
        ),
        en: "Rest, warm drinks and pay attention to unusual pains",
      ),
    ),
    WomenCyclePhase.follicular => WomenPhaseVisual(
      label: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'فاز فولیکولار',
          en: "Follicular phase",
        ),
        en: "Follicular phase",
      ),
      color: Color(0xFFB889E8),
      icon: Icons.auto_awesome_rounded,
      message: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'در این بخش از چرخه ممکنه انرژی و تمرکزت کم‌کم بیشتر بشه. شروع آرام کارهای تازه می‌تونه حس خوبی بده.',
          en: "In this part of the cycle, your energy and concentration may gradually increase. A slow start to new things can feel good.",
        ),
        en: "In this part of the cycle, your energy and concentration may gradually increase. A slow start to new things can feel good.",
      ),
      shortTip: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'حرکت سبک، برنامه‌ریزی و خواب منظم',
          en: "Light movement, planning and regular sleep",
        ),
        en: "Light movement, planning and regular sleep",
      ),
    ),
    WomenCyclePhase.fertile => WomenPhaseVisual(
      label: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'پنجره باروری تخمینی',
          en: "Estimated fertility window",
        ),
        en: "Estimated fertility window",
      ),
      color: Color(0xFF6F8DEB),
      icon: Icons.spa_rounded,
      message: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'این بازه فقط یک تخمین تقویمی است. ممکنه سطح انرژی یا میل به ارتباط بیشتر شود، اما تجربه هر بدن متفاوت است.',
          en: "This interval is only a calendar estimate. The energy level or the desire to communicate may increase, but each body's experience is different.",
        ),
        en: "This interval is only a calendar estimate. The energy level or the desire to communicate may increase, but each body's experience is different.",
      ),
      shortTip: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'آب کافی، فعالیت متعادل و توجه به نشانه‌های بدنت',
          en: "Adequate water, balanced activity and paying attention to your body's signs",
        ),
        en: "Adequate water, balanced activity and paying attention to your body's signs",
      ),
    ),
    WomenCyclePhase.ovulation => WomenPhaseVisual(
      label: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'روز تخمک‌گذاری تخمینی',
          en: "Estimated day of ovulation",
        ),
        en: "Estimated day of ovulation",
      ),
      color: Color(0xFF8B62D5),
      icon: Icons.local_florist_rounded,
      message: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'امروز براساس طول چرخه، روز تخمک‌گذاری تخمین زده شده؛ این تخمین اثبات پزشکی تخمک‌گذاری نیست.',
          en: "Today, based on the length of the cycle, the day of ovulation is estimated; This estimate is not medical proof of ovulation.",
        ),
        en: "Today, based on the length of the cycle, the day of ovulation is estimated; This estimate is not medical proof of ovulation.",
      ),
      shortTip: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'فعالیت متعادل و ثبت نشانه‌های واقعی بدن',
          en: "Balanced activity and registration of real body signs",
        ),
        en: "Balanced activity and registration of real body signs",
      ),
    ),
    WomenCyclePhase.luteal => WomenPhaseVisual(
      label: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(fa: 'فاز لوتئال', en: "Luteal phase"),
        en: "Luteal phase",
      ),
      color: Color(0xFFF3B35C),
      icon: Icons.wb_sunny_rounded,
      message: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'ممکنه در روزهای پیش رو انرژی کمی آرام‌تر شود. کارها را خرد کن و برای استراحت کوتاه جا باز بگذار.',
          en: "Energy may calm down a bit in the coming days. Break things up and leave room for short breaks.",
        ),
        en: "Energy may calm down a bit in the coming days. Break things up and leave room for short breaks.",
      ),
      shortTip: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'غذای متعادل، خواب کافی و فشار کمتر',
          en: "Balanced food, enough sleep and less stress",
        ),
        en: "Balanced food, enough sleep and less stress",
      ),
    ),
    WomenCyclePhase.pms => WomenPhaseVisual(
      label: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(fa: 'PMS تخمینی', en: "Estimated PMS"),
        en: "Estimated PMS",
      ),
      color: Color(0xFFE78374),
      icon: Icons.favorite_rounded,
      message: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'اگر حساس‌تر، خسته‌تر یا کم‌حوصله‌تری، با خودت مهربان‌تر باش. احساس امروزت معتبر است و ممکنه فردا متفاوت باشد.',
          en: "If you're more sensitive, tired, or depressed, be kinder to yourself. Your feeling today is valid and may be different tomorrow.",
        ),
        en: "If you're more sensitive, tired, or depressed, be kinder to yourself. Your feeling today is valid and may be different tomorrow.",
      ),
      shortTip: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'کاهش فشار، آب کافی و گفت‌وگوی صادقانه',
          en: "Pressure reduction, enough water and honest conversation",
        ),
        en: "Pressure reduction, enough water and honest conversation",
      ),
    ),
    null => WomenPhaseVisual(
      label: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'چرخه هنوز تنظیم نشده',
          en: "The cycle is not set yet",
        ),
        en: "The cycle is not set yet",
      ),
      color: womenLilac,
      icon: Icons.calendar_month_rounded,
      message: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'با ثبت تاریخ آخرین دوره، تقویم شخصی و تخمین‌های چرخه آماده می‌شوند.',
          en: "Personal calendar and cycle estimates are prepared by recording the date of the last cycle.",
        ),
        en: "Personal calendar and cycle estimates are prepared by recording the date of the last cycle.",
      ),
      shortTip: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'اطلاعات پایه چرخه را در تنظیمات ثبت کن',
          en: "Record the basic information of the cycle in the settings",
        ),
        en: "Record the basic information of the cycle in the settings",
      ),
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
      child: Material(color: Colors.transparent, child: child),
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
      padding: EdgeInsets.fromLTRB(18, 18, 18, 16),
      gradient: LinearGradient(
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
                          ? LifeMateRuntimeLocale.select(
                              fa: LifeMateRuntimeLocale.select(
                                fa: 'سلام عزیزم 💗',
                                en: "Hello my dear 💗",
                              ),
                              en: "Hello my dear 💗",
                            )
                          : LifeMateRuntimeLocale.select(
                              fa: LifeMateRuntimeLocale.select(
                                fa: 'سلام $ownerName جان 💗',
                                en: "Hello $ownerName John 💗",
                              ),
                              en: "Hello $ownerName John 💗",
                            ),
                      style: TextStyle(
                        color: womenInk,
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      hasCompanion
                          ? LifeMateRuntimeLocale.select(
                              fa: LifeMateRuntimeLocale.select(
                                fa: '$companionName همدل توست؛ فقط خلاصه‌ای که خودت اجازه بدهی می‌بیند.',
                                en: "$companionName is your companion and only sees the summaries you choose to share.",
                              ),
                              en: "$companionName is your sympathizer; It only sees the summary that you allow.",
                            )
                          : LifeMateRuntimeLocale.select(
                              fa: LifeMateRuntimeLocale.select(
                                fa: 'حال امروزت را ثبت کن؛ جزئیات خصوصی فقط برای خودت می‌ماند.',
                                en: "Record your current state; Private details remain only for you.",
                              ),
                              en: "Record your current state; Private details remain only for you.",
                            ),
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
                ? LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'چرخه تنظیم نشده',
                      en: "Cycle not set",
                    ),
                    en: "Cycle not set",
                  )
                : LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'روز ${value.cycleDay} از چرخه ${value.cycleLength} روزه',
                      en: "${value.cycleDay} day of cycle ${value.cycleLength} fast",
                    ),
                    en: "${value.cycleDay} day of cycle ${value.cycleLength} fast",
                  ),
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
                SizedBox(height: 4),
                Text(
                  value == null
                      ? LifeMateRuntimeLocale.select(
                          fa: 'روز چرخه',
                          en: "cycle day",
                        )
                      : LifeMateRuntimeLocale.select(
                          fa: 'از ${localizeDigits(context, value.cycleLength)} روز',
                          en: "of ${localizeDigits(context, value.cycleLength)} days",
                        ),
                  style: TextStyle(
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
                  SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      visual.label,
                      style: TextStyle(
                        color: womenInk,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              if (value != null) ...[
                SizedBox(height: 12),
                _CycleMetric(
                  icon: Icons.water_drop_outlined,
                  color: womenRose,
                  label: LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: '${localizeDigits(context, value.daysUntilNextPeriod)} روز تا دوره بعدی',
                      en: "${localizeDigits(context, value.daysUntilNextPeriod)} days until the next period",
                    ),
                    en: "${localizeDigits(context, value.daysUntilNextPeriod)} day to next period",
                  ),
                ),
                SizedBox(height: 8),
                _CycleMetric(
                  icon: Icons.local_florist_outlined,
                  color: womenLilac,
                  label: LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: '${localizeDigits(context, math.max(0, value.ovulationDay - value.cycleDay))} روز تا تخمک‌گذاری تخمینی',
                      en: "${localizeDigits(context, math.max(0, value.ovulationDay - value.cycleDay))} Days to Estimated Ovulation",
                    ),
                    en: "${localizeDigits(context, math.max(0, value.ovulationDay - value.cycleDay))} Days to Estimated Ovulation",
                  ),
                ),
              ],
              SizedBox(height: 13),
              OutlinedButton.icon(
                onPressed: onOpenCalendar,
                icon: Icon(Icons.calendar_month_rounded, size: 18),
                label: Text(
                  LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'تقویم چرخه',
                      en: "Cycle calendar",
                    ),
                    en: "Cycle calendar",
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: womenRose,
                  side: BorderSide(color: Color(0xFFF2A9C0)),
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

final womenMoods = <MoodDefinition>[
  MoodDefinition(
    'great',
    LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'عالی', en: "great"),
      en: "great",
    ),
    '😄',
    Color(0xFF61C7A0),
  ),
  MoodDefinition(
    'good',
    LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'خوب', en: "good"),
      en: "good",
    ),
    '🙂',
    Color(0xFF88B7EE),
  ),
  MoodDefinition(
    'neutral',
    LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'معمولی', en: "normal"),
      en: "normal",
    ),
    '😐',
    Color(0xFFF0C36B),
  ),
  MoodDefinition(
    'low',
    LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'کم‌حوصله', en: "bored"),
      en: "bored",
    ),
    '😔',
    Color(0xFFF0A06B),
  ),
  MoodDefinition(
    'overwhelmed',
    LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'تحت فشار', en: "under pressure"),
      en: "under pressure",
    ),
    '😣',
    Color(0xFFE5767F),
  ),
];

class SymptomDefinition {
  const SymptomDefinition(this.value, this.label, this.icon, this.color);
  final String value;
  final String label;
  final IconData icon;
  final Color color;
}

final womenSymptoms = <SymptomDefinition>[
  SymptomDefinition(
    'cramps',
    LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'درد شکم', en: "Abdominal pain"),
      en: "Abdominal pain",
    ),
    Icons.bolt_rounded,
    Color(0xFFF06B8B),
  ),
  SymptomDefinition(
    'headache',
    LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'سردرد', en: "headache"),
      en: "headache",
    ),
    Icons.psychology_alt_rounded,
    Color(0xFF9A78D2),
  ),
  SymptomDefinition(
    'bloating',
    LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'نفخ', en: "flatulence"),
      en: "flatulence",
    ),
    Icons.bubble_chart_rounded,
    Color(0xFFF2B15D),
  ),
  SymptomDefinition(
    'fatigue',
    LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'خستگی', en: "tiredness"),
      en: "tiredness",
    ),
    Icons.bedtime_rounded,
    Color(0xFF7B77D2),
  ),
  SymptomDefinition(
    'breast_tenderness',
    LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'حساسیت سینه',
        en: "Breast tenderness",
      ),
      en: "Breast tenderness",
    ),
    Icons.favorite_outline_rounded,
    Color(0xFFE87BA6),
  ),
  SymptomDefinition(
    'back_pain',
    LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'کمردرد', en: "back pain"),
      en: "back pain",
    ),
    Icons.accessibility_new_rounded,
    Color(0xFF7AA8D9),
  ),
  SymptomDefinition(
    'sleep_change',
    LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'تغییر خواب', en: "sleep change"),
      en: "sleep change",
    ),
    Icons.nights_stay_rounded,
    Color(0xFF836FC5),
  ),
  SymptomDefinition(
    'appetite_change',
    LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'تغییر اشتها',
        en: "Change in appetite",
      ),
      en: "Change in appetite",
    ),
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

final womenSupportNeeds = <SupportNeedDefinition>[
  SupportNeedDefinition(
    'none',
    LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'فعلاً خوبم', en: "I'm fine now"),
      en: "I'm fine now",
    ),
    Icons.check_circle_outline_rounded,
  ),
  SupportNeedDefinition(
    'rest',
    LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'استراحت', en: "rest"),
      en: "rest",
    ),
    Icons.bedtime_outlined,
  ),
  SupportNeedDefinition(
    'talk',
    LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'گفت‌وگو', en: "conversation"),
      en: "conversation",
    ),
    Icons.chat_bubble_outline_rounded,
  ),
  SupportNeedDefinition(
    'space',
    LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'کمی خلوت', en: "A little quiet"),
      en: "A little quiet",
    ),
    Icons.self_improvement_rounded,
  ),
  SupportNeedDefinition(
    'warmth',
    LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'نوشیدنی گرم', en: "hot drink"),
      en: "hot drink",
    ),
    Icons.local_cafe_outlined,
  ),
  SupportNeedDefinition(
    'walk',
    LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'پیاده‌روی', en: "walking"),
      en: "walking",
    ),
    Icons.directions_walk_rounded,
  ),
  SupportNeedDefinition(
    'hug',
    LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'آغوش', en: "hug"),
      en: "hug",
    ),
    Icons.favorite_border_rounded,
  ),
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
      key: ValueKey('women-daily-check-in-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WomenSectionHeader(
            title: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'حس و حال امروز من',
                en: "My mood today",
              ),
              en: "My mood today",
            ),
            subtitle: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'هر چیزی را که دوست داری ثبت کن؛ یادداشت و علائم خصوصی می‌مانند.',
                en: "Record anything you like; Notes and marks remain private.",
              ),
              en: "Record anything you like; Notes and marks remain private.",
            ),
            icon: Icons.emoji_emotions_outlined,
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 92,
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
                      padding: const EdgeInsets.symmetric(vertical: 7),
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
                          const SizedBox(height: 3),
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
          SizedBox(height: 16),
          Row(
            children: [
              Text(
                LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'انرژی امروز',
                    en: "Energy today",
                  ),
                  en: "Energy today",
                ),
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              Spacer(),
              Text(
                switch (energy) {
                  1 => LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'خیلی کم',
                      en: "very little",
                    ),
                    en: "very little",
                  ),
                  2 => LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(fa: 'کم', en: "low"),
                    en: "low",
                  ),
                  3 => LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'متوسط',
                      en: "average",
                    ),
                    en: "average",
                  ),
                  4 => LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(fa: 'خوب', en: "good"),
                    en: "good",
                  ),
                  _ => LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(fa: 'بالا', en: "up"),
                    en: "up",
                  ),
                },
                style: TextStyle(
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
          SizedBox(height: 8),
          Text(
            LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'علائم و نشانه‌ها',
                en: "Signs and symptoms",
              ),
              en: "Signs and symptoms",
            ),
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          SizedBox(height: 10),
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
          SizedBox(height: 16),
          Text(
            LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'امروز بیشتر به چی نیاز داری؟',
                en: "What do you need more today?",
              ),
              en: "What do you need more today?",
            ),
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          SizedBox(height: 10),
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
          SizedBox(height: 16),
          TextField(
            controller: noteController,
            maxLength: 500,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'یادداشت خصوصی امروز',
                  en: "Today's private note",
                ),
                en: "Today's private note",
              ),
              hintText: LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'حست، خوابت یا اتفاق مهم امروز را بنویس…',
                  en: "Write your feeling, dream or important event today...",
                ),
                en: "Write your feeling, dream or important event today...",
              ),
              prefixIcon: Icon(Icons.lock_outline_rounded),
              filled: true,
              fillColor: Color(0xFFFBF8FC),
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
            title: Text(
              LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'اشتراک خلاصه با همدل',
                  en: "Share the summary with empathy",
                ),
                en: "Share the summary with empathy",
              ),
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: Text(
              LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'فقط حال کلی، انرژی و نیاز حمایتی نمایش داده می‌شود؛ علائم و یادداشت خصوصی نیستند.',
                  en: "Only general mood, energy and need for support are displayed; Signs and notes are not private.",
                ),
                en: "Only general mood, energy and need for support are displayed; Signs and notes are not private.",
              ),
              style: TextStyle(fontSize: 10.5, height: 1.5),
            ),
          ),
          SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: saving ? null : onSave,
              icon: saving
                  ? SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.favorite_rounded),
              label: Text(
                saving
                    ? LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'در حال ذخیره…',
                          en: "Saving…",
                        ),
                        en: "Saving…",
                      )
                    : LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'ثبت حال امروز',
                          en: "Register today",
                        ),
                        en: "Register today",
                      ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: womenRose,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 14),
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
        colors: [visual.color.withValues(alpha: 0.16), Color(0xFFFFF9FC)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WomenSectionHeader(
            title: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'نکته امروز',
                en: "Today's tip",
              ),
              en: "Today's tip",
            ),
            subtitle: visual.label,
            icon: Icons.local_florist_rounded,
          ),
          SizedBox(height: 13),
          Text(
            visual.message,
            style: TextStyle(
              color: Color(0xFF5B4B66),
              height: 1.75,
              fontSize: 12.5,
            ),
          ),
          SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(17),
            ),
            child: Row(
              children: [
                Icon(Icons.eco_outlined, color: visual.color, size: 20),
                SizedBox(width: 9),
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
      key: ValueKey('women-emotional-14-day-timeline'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WomenSectionHeader(
            title: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: '۱۴ روز آینده',
                en: "next 14 days",
              ),
              en: "next 14 days",
            ),
            subtitle: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'هر روز را لمس کن تا فاز تخمینی و پیشنهاد ملایم همان روز را ببینی.',
                en: "Touch each day to see the estimated phase and soft offer for that day.",
              ),
              en: "Touch each day to see the estimated phase and soft offer for that day.",
            ),
            icon: Icons.timeline_rounded,
          ),
          SizedBox(height: 14),
          SizedBox(
            height: 119,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 14,
              separatorBuilder: (_, __) => SizedBox(width: 8),
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
                    duration: Duration(milliseconds: 180),
                    width: 72,
                    padding: EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: selected
                          ? dayVisual.color.withValues(alpha: 0.17)
                          : Color(0xFFFAF8FB),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: selected ? dayVisual.color : Color(0xFFF0ECF2),
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          index == 0
                              ? LifeMateRuntimeLocale.select(
                                  fa: 'امروز',
                                  en: "Today",
                                )
                              : localizeDigits(context, index),
                          style: TextStyle(
                            fontSize: index == 0 ? 10 : 14,
                            fontWeight: FontWeight.w900,
                            color: selected ? dayVisual.color : womenInk,
                          ),
                        ),
                        SizedBox(height: 7),
                        Icon(dayVisual.icon, size: 22, color: dayVisual.color),
                        SizedBox(height: 6),
                        Text(
                          formatAppDate(context, date, includeWeekday: false),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 8.5),
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
        ? LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'داده بیشتر لازم است',
              en: "More data is required",
            ),
            en: "More data is required",
          )
        : variation <= 7
        ? LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'نسبتاً منظم',
              en: "Fairly regular",
            ),
            en: "Fairly regular",
          )
        : LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(fa: 'متغیر', en: "Variable"),
            en: "Variable",
          );

    return WomenSoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WomenSectionHeader(
            title: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'گزارش‌های من',
                en: "My reports",
              ),
              en: "My reports",
            ),
            subtitle: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'خلاصه‌ای ساده از ثبت‌های واقعی؛ بدون تشخیص پزشکی.',
                en: "A simple summary of actual records; No medical diagnosis.",
              ),
              en: "A simple summary of actual records; No medical diagnosis.",
            ),
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
                  title: LifeMateRuntimeLocale.select(
                    fa: 'دوره‌های ثبت‌شده',
                    en: "Registered courses",
                  ),
                  value: localizeDigits(context, episodes.length),
                  icon: Icons.calendar_month_rounded,
                  color: womenRose,
                ),
                _ReportMetric(
                  title: LifeMateRuntimeLocale.select(
                    fa: 'میانگین طول چرخه',
                    en: "Average cycle length",
                  ),
                  value: avgCycle == null
                      ? '—'
                      : LifeMateRuntimeLocale.select(
                          fa: '${localizeDigits(context, avgCycle.round())} روز',
                          en: "${localizeDigits(context, avgCycle.round())} days",
                        ),
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
                  title: LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'الگوی چرخه',
                      en: "Cycle pattern",
                    ),
                    en: "Cycle pattern",
                  ),
                  value: regularity,
                  icon: Icons.show_chart_rounded,
                  color: womenPeach,
                ),
                _ReportMetric(
                  title: LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'علائم ثبت‌شده امروز',
                      en: "Signs registered today",
                    ),
                    en: "Signs registered today",
                  ),
                  value: localizeDigits(context, currentSymptoms.length),
                  icon: Icons.health_and_safety_outlined,
                  color: Color(0xFF6F8DEB),
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
          WomenSectionHeader(
            title: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'یادآوری‌ها',
                en: "Reminders",
              ),
              en: "Reminders",
            ),
            subtitle: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'چرخه و برنامه درمانی در یک نگاه',
                en: "Cycle and treatment plan at a glance",
              ),
              en: "Cycle and treatment plan at a glance",
            ),
            icon: Icons.notifications_active_outlined,
          ),
          SizedBox(height: 12),
          _ReminderRow(
            icon: Icons.water_drop_outlined,
            color: womenRose,
            title: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'نزدیک‌شدن دوره',
                en: "Approaching period",
              ),
              en: "Approaching period",
            ),
            value: !remindersEnabled
                ? 'خاموش'
                : estimate == null
                ? 'پس از تنظیم چرخه فعال می‌شود'
                : '${localizeDigits(context, estimate.daysUntilNextPeriod)} روز دیگر',
          ),
          SizedBox(height: 9),
          _ReminderRow(
            icon: Icons.medication_outlined,
            color: womenLilac,
            title: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'برنامه‌های درمانی فعال',
                en: "Active treatment programs",
              ),
              en: "Active treatment programs",
            ),
            value: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: '${localizeDigits(context, activeTreatmentCount)} برنامه',
                en: "${localizeDigits(context, activeTreatmentCount)} plans",
              ),
              en: "${localizeDigits(context, activeTreatmentCount)} app",
            ),
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
    color: Color(0xFFFFF8E9),
    borderColor: Color(0xFFF4DEAC),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.shield_outlined, color: Color(0xFF9B6D1A)),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'تاریخ‌ها و فازها تخمینی‌اند و جایگزین نظر پزشک نیستند. این بخش برای تشخیص، اثبات تخمک‌گذاری یا پیشگیری از بارداری استفاده نمی‌شود. علائم و یادداشت خصوصی به CareMate ارسال نمی‌شوند.',
                en: "Dates and phases are estimates and do not replace a doctor's opinion. This section is not used to diagnose, prove ovulation or prevent pregnancy. Signs and private notes are not sent to CareMate.",
              ),
              en: "Dates and phases are estimates and do not replace a doctor's opinion. This section is not used to diagnose, prove ovulation or prevent pregnancy. Signs and private notes are not sent to CareMate.",
            ),
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
