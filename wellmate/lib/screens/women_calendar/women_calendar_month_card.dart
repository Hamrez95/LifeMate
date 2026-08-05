import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:shamsi_date/shamsi_date.dart';

import '../../core/theme/app_style.dart';
import '../../core/utils/persian_date_utils.dart';

const _periodColor = Color(0xFFF45B78);
const _follicularColor = Color(0xFF9B7BD4);
const _fertileColor = Color(0xFF39BDB3);
const _ovulationColor = Color(0xFF2A91D8);
const _lutealColor = Color(0xFFF3B24C);
const _pmsColor = Color(0xFFE48166);
const _cycleTrackColor = Color(0xFFE9EDF1);

class WomenCalendarMonthCard extends StatefulWidget {
  const WomenCalendarMonthCard({
    super.key,
    required this.episodes,
    required this.estimate,
    this.initialFocusedDate,
  });

  final List<Map<String, dynamic>> episodes;
  final WomenCalendarEstimate? estimate;
  final DateTime? initialFocusedDate;

  @override
  State<WomenCalendarMonthCard> createState() => _WomenCalendarMonthCardState();
}

class _WomenCalendarMonthCardState extends State<WomenCalendarMonthCard> {
  late DateTime _focusedDate;

  @override
  void initState() {
    super.initState();
    _focusedDate = widget.initialFocusedDate ?? DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
    final range = visibleCalendarMonthRange(context, _focusedDate);
    final firstDate = _dateOnly(range.$1);
    final lastDate = _dateOnly(range.$2);
    final leadingEmptyCells = (firstDate.weekday + 1) % 7;
    final dayCount = lastDate.difference(firstDate).inDays + 1;
    final isPersian = usesPersianCalendar(context);
    final weekdayLabels = isPersian
        ? const ['ش', 'ی', 'د', 'س', 'چ', 'پ', 'ج']
        : const ['S', 'S', 'M', 'T', 'W', 'T', 'F'];
    final estimate = widget.estimate;
    final overviewDate = estimate?.today ?? DateTime.now();
    final recordedToday = _isRecordedBleedingDay(overviewDate);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 22,
            offset: Offset(0, 9),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (estimate != null)
            _CycleOverview(
              estimate: estimate,
              recordedToday: recordedToday,
            )
          else
            const _CycleOverviewEmpty(),
          const SizedBox(height: 18),
          const Divider(height: 1, color: Color(0xFFF0F2F5)),
          const SizedBox(height: 12),
          _MonthHeader(
            focusedDate: _focusedDate,
            onPrevious: () => _moveMonth(context, -1),
            onNext: () => _moveMonth(context, 1),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final label in weekdayLabels)
                Expanded(
                  child: Center(
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          GridView.builder(
            key: const ValueKey('women-calendar-month-grid'),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisExtent: 53,
              crossAxisSpacing: 4,
              mainAxisSpacing: 4,
            ),
            itemCount: leadingEmptyCells + dayCount,
            itemBuilder: (context, index) {
              if (index < leadingEmptyCells) return const SizedBox.shrink();
              final date = firstDate.add(
                Duration(days: index - leadingEmptyCells),
              );
              final actualBleeding = _isRecordedBleedingDay(date);
              final phase = estimate?.phaseForDate(date);
              final predictedPeriod =
                  !actualBleeding && phase == WomenCyclePhase.period;
              final isToday = _sameDay(date, DateTime.now());
              final dayNumber = isPersian
                  ? Jalali.fromDateTime(date).day
                  : date.day;
              final visual = _phaseVisual(phase);
              final background = actualBleeding
                  ? const Color(0xFFFFD4DF)
                  : predictedPeriod
                  ? const Color(0xFFFFEEF3)
                  : visual.background;
              final foreground = actualBleeding
                  ? const Color(0xFFB52E55)
                  : predictedPeriod
                  ? const Color(0xFFD3466B)
                  : visual.foreground;
              final statusLabel = actualBleeding
                  ? (isPersian
                        ? 'روز ثبت‌شده خون‌ریزی'
                        : 'Recorded bleeding day')
                  : phase == null
                  ? ''
                  : '${visual.label} ${isPersian ? 'تخمینی' : 'estimated'}';

              return Semantics(
                label: [
                  formatAppDate(context, date),
                  if (statusLabel.isNotEmpty) statusLabel,
                ].join('، '),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  decoration: BoxDecoration(
                    color: background,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isToday ? const Color(0xFF20B98A) : Colors.white,
                      width: isToday ? 1.8 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        localizeDigits(context, dayNumber),
                        maxLines: 1,
                        style: TextStyle(
                          color: foreground,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _DayPhaseMarker(
                        phase: phase,
                        actualBleeding: actualBleeding,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          const _CalendarLegend(),
          const SizedBox(height: 10),
          const Text(
            'این فازها بر پایه طول چرخه ثبت‌شده تخمین زده می‌شوند و برای تشخیص پزشکی یا پیشگیری از بارداری مناسب نیستند.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10.5,
              height: 1.5,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  void _moveMonth(BuildContext context, int delta) {
    setState(() {
      if (usesPersianCalendar(context)) {
        final current = Jalali.fromDateTime(_focusedDate);
        var year = current.year;
        var month = current.month + delta;
        if (month < 1) {
          month = 12;
          year -= 1;
        } else if (month > 12) {
          month = 1;
          year += 1;
        }
        _focusedDate = Jalali(year, month, 1).toDateTime();
      } else {
        _focusedDate = DateTime(
          _focusedDate.year,
          _focusedDate.month + delta,
          1,
        );
      }
    });
  }

  bool _isRecordedBleedingDay(DateTime date) {
    final day = _dateOnly(date);
    final today = _dateOnly(DateTime.now());
    for (final episode in widget.episodes) {
      final started = DateTime.tryParse(episode['startedOn']?.toString() ?? '');
      if (started == null) continue;
      final parsedEnd = DateTime.tryParse(episode['endedOn']?.toString() ?? '');
      final end = _dateOnly(parsedEnd ?? today);
      final start = _dateOnly(started);
      if (!day.isBefore(start) && !day.isAfter(end)) return true;
    }
    return false;
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.focusedDate,
    required this.onPrevious,
    required this.onNext,
  });

  final DateTime focusedDate;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final isPersian = usesPersianCalendar(context);
    return Directionality(
      textDirection: isPersian ? TextDirection.rtl : TextDirection.ltr,
      child: Row(
        children: [
          IconButton.filledTonal(
            tooltip: isPersian ? 'ماه قبل' : 'Previous month',
            onPressed: onPrevious,
            icon: Icon(
              isPersian
                  ? Icons.chevron_right_rounded
                  : Icons.chevron_left_rounded,
              textDirection: TextDirection.ltr,
            ),
          ),
          Expanded(
            child: Text(
              formatAppMonth(context, focusedDate),
              key: const ValueKey('women-calendar-month-title'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          IconButton.filledTonal(
            tooltip: isPersian ? 'ماه بعد' : 'Next month',
            onPressed: onNext,
            icon: Icon(
              isPersian
                  ? Icons.chevron_left_rounded
                  : Icons.chevron_right_rounded,
              textDirection: TextDirection.ltr,
            ),
          ),
        ],
      ),
    );
  }
}

class _DayPhaseMarker extends StatelessWidget {
  const _DayPhaseMarker({required this.phase, required this.actualBleeding});

  final WomenCyclePhase? phase;
  final bool actualBleeding;

  @override
  Widget build(BuildContext context) {
    if (actualBleeding) {
      return const Icon(Icons.water_drop_rounded, size: 11, color: _periodColor);
    }
    final visual = _phaseVisual(phase);
    if (phase == WomenCyclePhase.ovulation) {
      return Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: visual.color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(
              color: visual.color.withValues(alpha: 0.28),
              blurRadius: 5,
            ),
          ],
        ),
      );
    }
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(color: visual.color, shape: BoxShape.circle),
    );
  }
}

class _CycleOverview extends StatelessWidget {
  const _CycleOverview({
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
    final visual = _phaseVisual(phase);
    final phaseLabel = recordedToday ? 'دوره ثبت‌شده' : visual.label;
    final helperText = recordedToday
        ? 'اطلاعات امروز بر اساس دوره‌ای است که ثبت کرده‌اید.'
        : _phaseHelper(context, estimate, phase);

    return Column(
      key: const ValueKey('women-calendar-cycle-ring'),
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final diameter = constraints.maxWidth
                .clamp(230.0, 330.0)
                .toDouble();
            return SizedBox(
              width: diameter,
              height: diameter,
              child: Semantics(
                label:
                    'روز ${localizeDigits(context, estimate.cycleDay)} از چرخه، $phaseLabel',
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CustomPaint(
                      painter: _CycleRingPainter(
                        estimate: estimate,
                        dayLabel: localizeDigits(context, estimate.cycleDay),
                      ),
                    ),
                    Center(
                      child: Padding(
                        padding: EdgeInsets.all(diameter * 0.245),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              formatAppDate(context, estimate.today),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Icon(visual.icon, color: visual.color, size: 27),
                            const SizedBox(height: 7),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                phaseLabel,
                                key: const ValueKey(
                                  'women-calendar-cycle-phase',
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                            const SizedBox(height: 9),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 11,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: visual.color.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                'روز ${localizeDigits(context, estimate.cycleDay)} از ${localizeDigits(context, estimate.cycleLength)}',
                                key: const ValueKey(
                                  'women-calendar-cycle-day',
                                ),
                                maxLines: 1,
                                style: TextStyle(
                                  color: visual.color,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        Text(
          helperText,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.textSecondary,
            height: 1.55,
          ),
        ),
        const SizedBox(height: 14),
        const _PhaseLegend(),
      ],
    );
  }
}

class _CycleOverviewEmpty extends StatelessWidget {
  const _CycleOverviewEmpty();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('women-calendar-cycle-ring-empty'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF3F7), Color(0xFFF4F0FF)],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: const Column(
        children: [
          Icon(
            Icons.donut_large_rounded,
            size: 48,
            color: Color(0xFF9D69B8),
          ),
          SizedBox(height: 12),
          Text(
            'نمای چرخه پس از ثبت اطلاعات فعال می‌شود',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          SizedBox(height: 6),
          Text(
            'تاریخ شروع آخرین دوره، طول چرخه و مدت دوره را در تنظیمات ثبت کنید.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _CycleRingPainter extends CustomPainter {
  const _CycleRingPainter({required this.estimate, required this.dayLabel});

  final WomenCalendarEstimate estimate;
  final String dayLabel;

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = size.width * 0.073;
    final center = size.center(Offset.zero);
    final ringRect = Rect.fromCircle(
      center: center,
      radius: size.width / 2 - strokeWidth * 1.45,
    );
    const startAngle = -math.pi / 2;

    final trackPaint = Paint()
      ..color = _cycleTrackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(ringRect, 0, math.pi * 2, false, trackPaint);

    final segments = <_CycleSegment>[
      _CycleSegment(1, estimate.periodLength, _periodColor),
      _CycleSegment(
        estimate.periodLength + 1,
        estimate.fertileWindowStartDay - 1,
        _follicularColor,
      ),
      _CycleSegment(
        estimate.fertileWindowStartDay,
        estimate.ovulationDay - 1,
        _fertileColor,
      ),
      _CycleSegment(
        estimate.ovulationDay,
        estimate.ovulationDay,
        _ovulationColor,
      ),
      _CycleSegment(
        estimate.ovulationDay + 1,
        estimate.fertileWindowEndDay,
        _fertileColor,
      ),
      _CycleSegment(
        estimate.fertileWindowEndDay + 1,
        estimate.pmsStartDay - 1,
        _lutealColor,
      ),
      _CycleSegment(
        estimate.pmsStartDay,
        estimate.cycleLength,
        _pmsColor,
      ),
    ];

    for (final segment in segments) {
      if (segment.endDay < segment.startDay) continue;
      final start = startAngle +
          ((segment.startDay - 1) / estimate.cycleLength) * math.pi * 2;
      final fullSweep =
          ((segment.endDay - segment.startDay + 1) / estimate.cycleLength) *
          math.pi *
          2;
      final gap = math.min(0.045, fullSweep * 0.18);
      final paint = Paint()
        ..color = segment.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(ringRect, start + gap / 2, fullSweep - gap, false, paint);
    }

    final markerAngle = startAngle +
        ((estimate.cycleDay - 0.5) / estimate.cycleLength) * math.pi * 2;
    final markerRadius = ringRect.width / 2;
    final markerCenter = Offset(
      center.dx + math.cos(markerAngle) * markerRadius,
      center.dy + math.sin(markerAngle) * markerRadius,
    );
    final markerColor = _phaseVisual(estimate.detailedPhase).color;
    final markerRadiusValue = strokeWidth * 0.88;
    canvas.drawCircle(
      markerCenter,
      markerRadiusValue + 4,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      markerCenter,
      markerRadiusValue,
      Paint()..color = markerColor,
    );

    final textPainter = TextPainter(
      text: TextSpan(
        text: dayLabel,
        style: TextStyle(
          color: Colors.white,
          fontSize: markerRadiusValue * 0.85,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.rtl,
      textAlign: TextAlign.center,
    )..layout(maxWidth: markerRadiusValue * 1.8);
    textPainter.paint(
      canvas,
      markerCenter - Offset(textPainter.width / 2, textPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _CycleRingPainter oldDelegate) =>
      oldDelegate.estimate.cycleDay != estimate.cycleDay ||
      oldDelegate.estimate.cycleLength != estimate.cycleLength ||
      oldDelegate.estimate.periodLength != estimate.periodLength ||
      oldDelegate.dayLabel != dayLabel;
}

class _CycleSegment {
  const _CycleSegment(this.startDay, this.endDay, this.color);

  final int startDay;
  final int endDay;
  final Color color;
}

class _PhaseLegend extends StatelessWidget {
  const _PhaseLegend();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: const [
        _LegendChip(label: 'قاعدگی', color: _periodColor),
        _LegendChip(label: 'فولیکولار', color: _follicularColor),
        _LegendChip(label: 'باروری', color: _fertileColor),
        _LegendChip(label: 'تخمک‌گذاری', color: _ovulationColor),
        _LegendChip(label: 'لوتئال', color: _lutealColor),
        _LegendChip(label: 'PMS', color: _pmsColor),
      ],
    );
  }
}

class _CalendarLegend extends StatelessWidget {
  const _CalendarLegend();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: const [
        _LegendChip(label: 'ثبت‌شده', color: Color(0xFFB52E55)),
        _LegendChip(label: 'قاعدگی تخمینی', color: _periodColor),
        _LegendChip(label: 'باروری', color: _fertileColor),
        _LegendChip(label: 'تخمک‌گذاری', color: _ovulationColor),
        _LegendChip(label: 'PMS', color: _pmsColor),
      ],
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _PhaseVisual {
  const _PhaseVisual({
    required this.label,
    required this.color,
    required this.background,
    required this.foreground,
    required this.icon,
  });

  final String label;
  final Color color;
  final Color background;
  final Color foreground;
  final IconData icon;
}

_PhaseVisual _phaseVisual(WomenCyclePhase? phase) => switch (phase) {
      WomenCyclePhase.period => const _PhaseVisual(
          label: 'قاعدگی',
          color: _periodColor,
          background: Color(0xFFFFF0F4),
          foreground: Color(0xFFB52E55),
          icon: Icons.water_drop_rounded,
        ),
      WomenCyclePhase.follicular => const _PhaseVisual(
          label: 'فاز فولیکولار',
          color: _follicularColor,
          background: Color(0xFFF5F1FC),
          foreground: Color(0xFF7352A5),
          icon: Icons.auto_awesome_rounded,
        ),
      WomenCyclePhase.fertile => const _PhaseVisual(
          label: 'پنجره باروری تخمینی',
          color: _fertileColor,
          background: Color(0xFFECFAF8),
          foreground: Color(0xFF1C827B),
          icon: Icons.spa_rounded,
        ),
      WomenCyclePhase.ovulation => const _PhaseVisual(
          label: 'روز تخمک‌گذاری تخمینی',
          color: _ovulationColor,
          background: Color(0xFFEDF7FD),
          foreground: Color(0xFF17699E),
          icon: Icons.blur_circular_rounded,
        ),
      WomenCyclePhase.luteal => const _PhaseVisual(
          label: 'فاز لوتئال',
          color: _lutealColor,
          background: Color(0xFFFFF8EA),
          foreground: Color(0xFF9B6D19),
          icon: Icons.wb_sunny_outlined,
        ),
      WomenCyclePhase.pms => const _PhaseVisual(
          label: 'PMS تخمینی',
          color: _pmsColor,
          background: Color(0xFFFFF1ED),
          foreground: Color(0xFFA74D39),
          icon: Icons.favorite_border_rounded,
        ),
      null => const _PhaseVisual(
          label: 'بدون تخمین',
          color: Color(0xFFB8C0C8),
          background: Color(0xFFF8F9FB),
          foreground: AppColors.textPrimary,
          icon: Icons.circle_outlined,
        ),
    };

String _phaseHelper(
  BuildContext context,
  WomenCalendarEstimate estimate,
  WomenCyclePhase phase,
) =>
    switch (phase) {
      WomenCyclePhase.period =>
        'امروز در بازه تخمینی قاعدگی قرار دارد؛ ثبت واقعی شما همیشه اولویت دارد.',
      WomenCyclePhase.follicular =>
        'فاز فولیکولار تخمینی است؛ انرژی و علائم هر فرد می‌تواند متفاوت باشد.',
      WomenCyclePhase.fertile =>
        'پنجره باروری فقط بر پایه طول چرخه تخمین زده شده و روش پیشگیری محسوب نمی‌شود.',
      WomenCyclePhase.ovulation =>
        'روز تخمک‌گذاری تخمینی است و بدون داده یا آزمایش پزشکی قطعی نیست.',
      WomenCyclePhase.luteal =>
        'فاز لوتئال تخمینی تا شروع دوره بعدی ادامه دارد.',
      WomenCyclePhase.pms =>
        'حدود ${localizeDigits(context, estimate.daysUntilNextPeriod)} روز تا شروع دوره بعدی باقی مانده است.',
    };

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

bool _sameDay(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;
