part of 'women_cycle_character_card.dart';

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .75),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: color.withValues(alpha: .18)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    ),
  );
}

class _Cloud extends StatelessWidget {
  const _Cloud({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: .35,
    child: Container(
      width: width,
      height: width * .35,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(width),
      ),
    ),
  );
}

class _HintRow extends StatelessWidget {
  const _HintRow({required this.phase});

  final WomenCyclePhase phase;

  @override
  Widget build(BuildContext context) {
    final items = switch (phase) {
      WomenCyclePhase.period => [
        (LifeMateRuntimeLocale.select(fa: 'حساسیت', en: 'Sensitivity'), Icons.eco_rounded),
        (LifeMateRuntimeLocale.select(fa: 'احساس خستگی', en: 'Tiredness'), Icons.cloud_rounded),
        (LifeMateRuntimeLocale.select(fa: 'درد شکم', en: 'Cramps'), Icons.bolt_rounded),
        (LifeMateRuntimeLocale.select(fa: 'نفخ', en: 'Bloating'), Icons.bubble_chart_rounded),
        (LifeMateRuntimeLocale.select(fa: 'کمر درد', en: 'Back pain'), Icons.accessibility_new_rounded),
      ],
      WomenCyclePhase.follicular => [
        (LifeMateRuntimeLocale.select(fa: 'انرژی', en: 'Energy'), Icons.bolt_rounded),
        (LifeMateRuntimeLocale.select(fa: 'تمرکز', en: 'Focus'), Icons.center_focus_strong_rounded),
        (LifeMateRuntimeLocale.select(fa: 'تحرک', en: 'Movement'), Icons.directions_walk_rounded),
        (LifeMateRuntimeLocale.select(fa: 'شادابی', en: 'Vitality'), Icons.auto_awesome_rounded),
      ],
      WomenCyclePhase.fertile => [
        (LifeMateRuntimeLocale.select(fa: 'شادابی', en: 'Vitality'), Icons.favorite_rounded),
        (LifeMateRuntimeLocale.select(fa: 'انرژی', en: 'Energy'), Icons.auto_awesome_rounded),
        (LifeMateRuntimeLocale.select(fa: 'تعادل', en: 'Balance'), Icons.spa_rounded),
        (LifeMateRuntimeLocale.select(fa: 'تمرکز', en: 'Focus'), Icons.center_focus_strong_rounded),
      ],
      WomenCyclePhase.ovulation => [
        (LifeMateRuntimeLocale.select(fa: 'شادابی', en: 'Vitality'), Icons.favorite_rounded),
        (LifeMateRuntimeLocale.select(fa: 'انرژی', en: 'Energy'), Icons.auto_awesome_rounded),
        (LifeMateRuntimeLocale.select(fa: 'تعادل', en: 'Balance'), Icons.spa_rounded),
        (LifeMateRuntimeLocale.select(fa: 'تحرک', en: 'Movement'), Icons.directions_walk_rounded),
      ],
      WomenCyclePhase.luteal => [
        (LifeMateRuntimeLocale.select(fa: 'آرامش', en: 'Calm'), Icons.self_improvement_rounded),
        (LifeMateRuntimeLocale.select(fa: 'خواب', en: 'Rest'), Icons.bedtime_rounded),
        (LifeMateRuntimeLocale.select(fa: 'تعادل', en: 'Balance'), Icons.spa_rounded),
        (LifeMateRuntimeLocale.select(fa: 'استراحت', en: 'Recovery'), Icons.nightlight_round),
      ],
      WomenCyclePhase.pms => [
        (LifeMateRuntimeLocale.select(fa: 'حساسیت', en: 'Sensitivity'), Icons.favorite_rounded),
        (LifeMateRuntimeLocale.select(fa: 'کم‌حوصلگی', en: 'Irritability'), Icons.thunderstorm_rounded),
        (LifeMateRuntimeLocale.select(fa: 'استراحت', en: 'Rest'), Icons.bedtime_rounded),
        (LifeMateRuntimeLocale.select(fa: 'نفخ', en: 'Bloating'), Icons.bubble_chart_rounded),
        (LifeMateRuntimeLocale.select(fa: 'کمر درد', en: 'Back pain'), Icons.accessibility_new_rounded),
      ],
    };
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final item in items)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .62),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFFD7E1)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(item.$2, size: 14, color: const Color(0xFF8E6CB7)),
                const SizedBox(width: 4),
                Text(
                  item.$1,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF6E5A70),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Stage {
  const _Stage(this.label, this.range, this.asset, this.color);

  final String label;
  final String range;
  final String asset;
  final Color color;
}

List<_Stage> _upcoming(WomenCalendarEstimate estimate, WomenCyclePhase phase) {
  final stages = <_Stage>[
    _Stage(
      LifeMateRuntimeLocale.select(fa: 'دوره قاعدگی', en: 'Period'),
      LifeMateRuntimeLocale.select(
        fa: 'روز ۱ تا ${estimate.periodLength}',
        en: 'Day 1–${estimate.periodLength}',
      ),
      _periodAsset,
      _periodColor,
    ),
    _Stage(
      LifeMateRuntimeLocale.select(fa: 'فاز فولیکولی', en: 'Follicular phase'),
      LifeMateRuntimeLocale.select(
        fa: 'روز ${estimate.periodLength + 1} تا ${estimate.fertilityEstimateReliable ? estimate.fertileWindowStartDay - 1 : estimate.pmsStartDay - 1}',
        en: 'Day ${estimate.periodLength + 1}–${estimate.fertilityEstimateReliable ? estimate.fertileWindowStartDay - 1 : estimate.pmsStartDay - 1}',
      ),
      _follicularAsset,
      _follicularColor,
    ),
    if (estimate.fertilityEstimateReliable)
      _Stage(
        LifeMateRuntimeLocale.select(fa: 'روزهای باروری', en: 'Fertile window'),
        LifeMateRuntimeLocale.select(
          fa: 'روز ${estimate.fertileWindowStartDay} تا ${estimate.fertileWindowEndDay}',
          en: 'Day ${estimate.fertileWindowStartDay}–${estimate.fertileWindowEndDay}',
        ),
        _ovulationAsset,
        _fertileColor,
      ),
    if (estimate.fertilityEstimateReliable)
      _Stage(
        LifeMateRuntimeLocale.select(fa: 'تخمک‌گذاری', en: 'Ovulation'),
        LifeMateRuntimeLocale.select(
          fa: 'حدود روز ${estimate.ovulationDay}',
          en: 'Around day ${estimate.ovulationDay}',
        ),
        _ovulationAsset,
        _ovulationColor,
      ),
    _Stage(
      LifeMateRuntimeLocale.select(fa: 'فاز لوتئال', en: 'Luteal phase'),
      estimate.fertilityEstimateReliable
          ? LifeMateRuntimeLocale.select(
              fa: 'روز ${estimate.fertileWindowEndDay + 1} تا ${estimate.pmsStartDay - 1}',
              en: 'Day ${estimate.fertileWindowEndDay + 1}–${estimate.pmsStartDay - 1}',
            )
          : LifeMateRuntimeLocale.select(fa: 'پیش از PMS', en: 'Before PMS'),
      _lutealAsset,
      _lutealColor,
    ),
    _Stage(
      'PMS',
      LifeMateRuntimeLocale.select(
        fa: 'روز ${estimate.pmsStartDay} تا ${estimate.cycleLength}',
        en: 'Day ${estimate.pmsStartDay}–${estimate.cycleLength}',
      ),
      _pmsAsset,
      _pmsColor,
    ),
  ];

  final current = switch (phase) {
    WomenCyclePhase.period => 0,
    WomenCyclePhase.follicular => 1,
    WomenCyclePhase.fertile => estimate.fertilityEstimateReliable ? 2 : 1,
    WomenCyclePhase.ovulation => estimate.fertilityEstimateReliable ? 3 : 1,
    WomenCyclePhase.luteal => estimate.fertilityEstimateReliable ? 4 : 2,
    WomenCyclePhase.pms => stages.length - 1,
  };
  final result = <_Stage>[];
  for (var i = 1; i <= stages.length && result.length < 4; i++) {
    result.add(stages[(current + i) % stages.length]);
  }
  return result;
}

class _StageCard extends StatelessWidget {
  const _StageCard({required this.stage});

  final _Stage stage;

  @override
  Widget build(BuildContext context) => Container(
    width: 112,
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: stage.color.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.white),
    ),
    child: Column(
      children: [
        Expanded(
          child: Image.asset(
            stage.asset,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            errorBuilder: (_, __, ___) => Icon(
              Icons.favorite_rounded,
              color: stage.color,
              size: 36,
            ),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          stage.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w900,
            color: stage.color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          localizeDigits(context, stage.range),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 9, color: AppColors.textSecondary),
        ),
      ],
    ),
  );
}

class _Visual {
  const _Visual(
    this.label,
    this.color,
    this.background,
    this.foreground,
    this.asset,
    this.icon,
  );

  final String label;
  final Color color;
  final Color background;
  final Color foreground;
  final String asset;
  final IconData icon;
}

_Visual _visual(WomenCyclePhase? phase) => switch (phase) {
  WomenCyclePhase.period => _Visual(
    LifeMateRuntimeLocale.select(fa: 'دوره قاعدگی', en: 'Period'),
    _periodColor,
    const Color(0xFFFFEDF2),
    const Color(0xFFB52E55),
    _periodAsset,
    Icons.water_drop_rounded,
  ),
  WomenCyclePhase.follicular => _Visual(
    LifeMateRuntimeLocale.select(fa: 'فولیکولار', en: 'Follicular'),
    _follicularColor,
    const Color(0xFFF5F0FF),
    const Color(0xFF6C4AA0),
    _follicularAsset,
    Icons.eco_rounded,
  ),
  WomenCyclePhase.fertile => _Visual(
    LifeMateRuntimeLocale.select(fa: 'باروری', en: 'Fertile'),
    _fertileColor,
    const Color(0xFFEAFBF8),
    const Color(0xFF208A83),
    _ovulationAsset,
    Icons.favorite_rounded,
  ),
  WomenCyclePhase.ovulation => _Visual(
    LifeMateRuntimeLocale.select(fa: 'تخمک‌گذاری', en: 'Ovulation'),
    _ovulationColor,
    const Color(0xFFEAF6FF),
    const Color(0xFF2375B0),
    _ovulationAsset,
    Icons.favorite_rounded,
  ),
  WomenCyclePhase.luteal => _Visual(
    LifeMateRuntimeLocale.select(fa: 'لوتئال', en: 'Luteal'),
    _lutealColor,
    const Color(0xFFFFF7E8),
    const Color(0xFFA87520),
    _lutealAsset,
    Icons.self_improvement_rounded,
  ),
  WomenCyclePhase.pms => _Visual(
    'PMS',
    _pmsColor,
    const Color(0xFFFFEFEA),
    const Color(0xFFB75E48),
    _pmsAsset,
    Icons.thunderstorm_rounded,
  ),
  null => _Visual(
    '',
    const Color(0xFF9B7BD4),
    const Color(0xFFF7F3FB),
    const Color(0xFF7B5AA7),
    _follicularAsset,
    Icons.circle_outlined,
  ),
};

String _supportCopy(BuildContext _, WomenCyclePhase phase) => switch (phase) {
  WomenCyclePhase.period => LifeMateRuntimeLocale.select(
    fa: '💗 بدنت شگفت‌انگیزه؛ امروز کمی بیشتر با خودت مهربان باش.',
    en: '💗 Your body is doing a lot. Be a little gentler with yourself today.',
  ),
  WomenCyclePhase.follicular => LifeMateRuntimeLocale.select(
    fa: '🌱 انرژی کم‌کم برمی‌گرده؛ با ریتم خودت جلو برو.',
    en: '🌱 Energy may be returning. Move at your own pace.',
  ),
  WomenCyclePhase.fertile => LifeMateRuntimeLocale.select(
    fa: '✨ این فقط یک برآورد تقویمی از چرخه توست.',
    en: '✨ This is only a calendar-based cycle estimate.',
  ),
  WomenCyclePhase.ovulation => LifeMateRuntimeLocale.select(
    fa: '💞 زمان تخمک‌گذاری تخمینی است، نه تشخیص پزشکی.',
    en: '💞 Ovulation timing is an estimate, not a medical diagnosis.',
  ),
  WomenCyclePhase.luteal => LifeMateRuntimeLocale.select(
    fa: '☁️ آرام‌تر شدن طبیعی است؛ به خواب و استراحتت توجه کن.',
    en: '☁️ A slower rhythm can be normal. Make room for rest.',
  ),
  WomenCyclePhase.pms => LifeMateRuntimeLocale.select(
    fa: '💜 احساساتت مهم‌اند؛ امروز با خودت صبورتر باش.',
    en: '💜 Your feelings matter. Give yourself more patience today.',
  ),
};
