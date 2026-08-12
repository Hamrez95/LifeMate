import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';

import '../../core/theme/app_style.dart';
import '../../core/utils/persian_date_utils.dart';

part 'women_cycle_character_card_parts.dart';

const _periodColor = Color(0xFFF45B78);
const _follicularColor = Color(0xFF9B7BD4);
const _fertileColor = Color(0xFF39BDB3);
const _ovulationColor = Color(0xFF2A91D8);
const _lutealColor = Color(0xFFF3B24C);
const _pmsColor = Color(0xFFE48166);
const _trackColor = Color(0xFFF6DDE5);
const _periodAsset = 'feature_assets/women_cycle/period.webp';
const _follicularAsset = 'feature_assets/women_cycle/follicular.webp';
const _ovulationAsset = 'feature_assets/women_cycle/ovulation.webp';
const _lutealAsset = 'feature_assets/women_cycle/luteal.webp';
const _pmsAsset = 'feature_assets/women_cycle/pms.webp';

class WomenCycleCharacterCard extends StatelessWidget {
  const WomenCycleCharacterCard({
    super.key,
    required this.estimate,
    required this.recordedToday,
  });

  final WomenCalendarEstimate estimate;
  final bool recordedToday;

  @override
  Widget build(BuildContext context) {
    final phase = recordedToday
        ? WomenCyclePhase.period
        : estimate.detailedPhase;
    final visual = _visual(phase);
    final stages = _majorUpcoming(estimate);

    return Container(
      key: const ValueKey('women-calendar-cycle-ring'),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFFEFF4),
            Color(0xFFF9ECFF),
            Color(0xFFFFF4EA),
          ],
        ),
        border: Border.all(color: const Color(0xFFFFD7E1)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x18E07799),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          const Positioned(right: -36, top: 58, child: _Cloud(width: 120)),
          const Positioned(left: -26, top: 150, child: _Cloud(width: 96)),
          const Positioned(
            right: 26,
            top: 14,
            child: Icon(
              Icons.auto_awesome_rounded,
              size: 17,
              color: Color(0xFFFFB3C6),
            ),
          ),
          Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _Pill(
                      icon: Icons.calendar_month_rounded,
                      label: formatAppDate(context, estimate.today),
                      color: const Color(0xFF7D5AB4),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _Pill(
                      icon: visual.icon,
                      label: visual.label,
                      color: visual.color,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (context, constraints) {
                  final size = math.min(270.0, constraints.maxWidth);
                  return SizedBox.square(
                    dimension: size,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CustomPaint(
                          size: Size.square(size),
                          painter: _CyclePainter(
                            estimate: estimate,
                            phase: phase,
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.all(size * .15),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                visual.label,
                                key: const ValueKey(
                                  'women-calendar-cycle-phase',
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 21,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF28273B),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 13,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: .76),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: visual.color.withValues(alpha: .2),
                                  ),
                                ),
                                child: Text(
                                  LifeMateRuntimeLocale.select(
                                    fa: 'روز ${localizeDigits(context, estimate.cycleDay)} از ${localizeDigits(context, estimate.cycleLength)}',
                                    en: 'Day ${estimate.cycleDay} of ${estimate.cycleLength}',
                                  ),
                                  key: const ValueKey(
                                    'women-calendar-cycle-day',
                                  ),
                                  style: TextStyle(
                                    color: visual.color,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 5),
                              SizedBox(
                                height: size * .34,
                                child: Image.asset(
                                  visual.asset,
                                  key: const ValueKey(
                                    'women-calendar-current-phase-character',
                                  ),
                                  fit: BoxFit.contain,
                                  filterQuality: FilterQuality.high,
                                  semanticLabel: visual.label,
                                  errorBuilder: (_, __, ___) => Icon(
                                    visual.icon,
                                    color: visual.color,
                                    size: 68,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 5),
              Text(
                _supportCopy(context, phase),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.45,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF6E5A70),
                ),
              ),
              const SizedBox(height: 9),
              _HintRow(phase: phase),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Expanded(
                    child: Divider(color: Color(0xFFFFC8D7)),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(
                      Icons.auto_awesome_rounded,
                      size: 15,
                      color: Color(0xFFFF9DB6),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      LifeMateRuntimeLocale.select(
                        fa: 'مراحل پیش رو',
                        en: 'Coming next',
                      ),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF3D3848),
                      ),
                    ),
                  ),
                  const Expanded(
                    child: Divider(color: Color(0xFFFFC8D7)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 150,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: stages.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) => _StageCard(stage: stages[i]),
                ),
              ),
              if (!estimate.fertilityEstimateReliable) ...[
                const SizedBox(height: 9),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .68),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFFFD7E1)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        size: 17,
                        color: Color(0xFF936AC8),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          LifeMateRuntimeLocale.select(
                            fa: estimate.pattern == WomenCyclePattern.variable
                                ? 'چرخه‌ها متغیرند؛ زمان باروری فعلاً نمایش داده نمی‌شود.'
                                : 'برای نمایش زمان باروری، چند شروع دوره دیگر ثبت کن.',
                            en: estimate.pattern == WomenCyclePattern.variable
                                ? 'Your cycles vary, so fertility timing is hidden.'
                                : 'Log a few more period starts before fertility timing is shown.',
                          ),
                          style: const TextStyle(
                            fontSize: 10.5,
                            height: 1.4,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _CyclePainter extends CustomPainter {
  const _CyclePainter({required this.estimate, required this.phase});

  final WomenCalendarEstimate estimate;
  final WomenCyclePhase phase;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 17;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18
      ..strokeCap = StrokeCap.round
      ..color = _trackColor;
    canvas.drawArc(rect, 0, math.pi * 2, false, track);

    final segments = _segments(estimate);
    final total = segments.fold<double>(0, (v, s) => v + s.$2);
    var cursor = -math.pi / 2;
    for (final item in segments) {
      final raw = item.$2 / total * math.pi * 2;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 18
        ..strokeCap = StrokeCap.round
        ..color = item.$1;
      canvas.drawArc(
        rect,
        cursor + .01,
        math.max(.01, raw - .02),
        false,
        paint,
      );
      cursor += raw;
    }

    final progress = ((estimate.cycleDay - .5) / estimate.cycleLength).clamp(
      0.0,
      1.0,
    );
    final angle = -math.pi / 2 + math.pi * 2 * progress;
    final p = Offset(
      center.dx + math.cos(angle) * radius,
      center.dy + math.sin(angle) * radius,
    );
    final c = _visual(phase).color;
    canvas.drawCircle(p, 18, Paint()..color = Colors.white);
    canvas.drawCircle(p, 13.5, Paint()..color = c);

    final heart = TextPainter(
      text: const TextSpan(
        text: '♥',
        style: TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    heart.paint(canvas, p - Offset(heart.width / 2, heart.height / 2 + 1));
  }

  @override
  bool shouldRepaint(covariant _CyclePainter old) {
    return old.phase != phase ||
        old.estimate.cycleDay != estimate.cycleDay ||
        old.estimate.cycleLength != estimate.cycleLength ||
        old.estimate.periodLength != estimate.periodLength ||
        old.estimate.fertileWindowStartDay != estimate.fertileWindowStartDay ||
        old.estimate.fertileWindowEndDay != estimate.fertileWindowEndDay ||
        old.estimate.ovulationDay != estimate.ovulationDay ||
        old.estimate.pmsStartDay != estimate.pmsStartDay ||
        old.estimate.fertilityEstimateReliable !=
            estimate.fertilityEstimateReliable;
  }
}

List<(Color, double)> _segments(WomenCalendarEstimate e) {
  final pms = math.max(1, e.cycleLength - e.pmsStartDay + 1).toDouble();
  if (!e.fertilityEstimateReliable) {
    final middle = math.max(1, e.pmsStartDay - e.periodLength - 1).toDouble();
    return [
      (_periodColor, e.periodLength.toDouble()),
      (_follicularColor, middle),
      (_pmsColor, pms),
    ];
  }

  final follicular = math
      .max(1, e.fertileWindowStartDay - e.periodLength - 1)
      .toDouble();
  final fertileBefore = math
      .max(1, e.ovulationDay - e.fertileWindowStartDay)
      .toDouble();
  final fertileAfter = math
      .max(1, e.fertileWindowEndDay - e.ovulationDay)
      .toDouble();
  final luteal = math
      .max(1, e.pmsStartDay - e.fertileWindowEndDay - 1)
      .toDouble();
  return [
    (_periodColor, e.periodLength.toDouble()),
    (_follicularColor, follicular),
    (_fertileColor, fertileBefore),
    (_ovulationColor, 1),
    (_fertileColor, fertileAfter),
    (_lutealColor, luteal),
    (_pmsColor, pms),
  ];
}

List<_Stage> _majorUpcoming(WomenCalendarEstimate estimate) {
  final reliable = estimate.fertilityEstimateReliable;
  final stages = <_Stage>[
    _Stage(
      LifeMateRuntimeLocale.select(fa: 'قاعدگی بعدی', en: 'Next period'),
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
        fa: 'روز ${estimate.periodLength + 1} تا ${reliable ? estimate.fertileWindowStartDay - 1 : estimate.pmsStartDay - 1}',
        en: 'Day ${estimate.periodLength + 1}–${reliable ? estimate.fertileWindowStartDay - 1 : estimate.pmsStartDay - 1}',
      ),
      _follicularAsset,
      _follicularColor,
    ),
    if (reliable)
      _Stage(
        LifeMateRuntimeLocale.select(fa: 'روزهای باروری', en: 'Fertile window'),
        LifeMateRuntimeLocale.select(
          fa: 'روز ${estimate.fertileWindowStartDay} تا ${estimate.fertileWindowEndDay}',
          en: 'Day ${estimate.fertileWindowStartDay}–${estimate.fertileWindowEndDay}',
        ),
        _ovulationAsset,
        _fertileColor,
      ),
    if (reliable)
      _Stage(
        LifeMateRuntimeLocale.select(fa: 'فاز لوتئال', en: 'Luteal phase'),
        LifeMateRuntimeLocale.select(
          fa: 'روز ${estimate.fertileWindowEndDay + 1} تا ${estimate.pmsStartDay - 1}',
          en: 'Day ${estimate.fertileWindowEndDay + 1}–${estimate.pmsStartDay - 1}',
        ),
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

  final current = !reliable
      ? (estimate.cycleDay <= estimate.periodLength
            ? 0
            : estimate.cycleDay >= estimate.pmsStartDay
            ? 2
            : 1)
      : (estimate.cycleDay <= estimate.periodLength
            ? 0
            : estimate.cycleDay < estimate.fertileWindowStartDay
            ? 1
            : estimate.cycleDay <= estimate.fertileWindowEndDay
            ? 2
            : estimate.cycleDay < estimate.pmsStartDay
            ? 3
            : 4);

  final count = math.min(4, math.max(0, stages.length - 1));
  return [
    for (var offset = 1; offset <= count; offset++)
      stages[(current + offset) % stages.length],
  ];
}
