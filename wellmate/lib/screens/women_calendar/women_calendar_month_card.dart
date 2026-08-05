import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:shamsi_date/shamsi_date.dart';

import '../../core/theme/app_style.dart';
import '../../core/utils/persian_date_utils.dart';

const _periodColor = Color(0xFFFF5B72);
const _postPeriodColor = Color(0xFFB99ADE);
const _cycleColor = Color(0xFF28C4BF);
const _prePeriodColor = Color(0xFFFFB02E);
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
          const SizedBox(height: 14),
          Directionality(
            textDirection: isPersian
                ? TextDirection.rtl
                : TextDirection.ltr,
            child: Row(
              children: [
                IconButton(
                  tooltip: isPersian ? 'ماه قبل' : 'Previous month',
                  onPressed: () => _moveMonth(context, -1),
                  icon: Icon(
                    isPersian
                        ? Icons.chevron_right_rounded
                        : Icons.chevron_left_rounded,
                    textDirection: TextDirection.ltr,
                  ),
                ),
                Expanded(
                  child: Text(
                    formatAppMonth(context, _focusedDate),
                    key: const ValueKey('women-calendar-month-title'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: isPersian ? 'ماه بعد' : 'Next month',
                  onPressed: () => _moveMonth(context, 1),
                  icon: Icon(
                    isPersian
                        ? Icons.chevron_left_rounded
                        : Icons.chevron_right_rounded,
                    textDirection: TextDirection.ltr,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final label in weekdayLabels)
                Expanded(
                  child: Center(
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
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
              mainAxisExtent: 52,
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
              final estimatedBleeding =
                  !actualBleeding && estimate?.isEstimatedPeriodDay(date) == true;
              final phase = _phaseForDate(date, estimate);
              final isToday = _sameDay(date, DateTime.now());
              final dayNumber = isPersian
                  ? Jalali.fromDateTime(date).day
                  : date.day;
              final foreground = actualBleeding
                  ? const Color(0xFFB52E55)
                  : estimatedBleeding
                  ? const Color(0xFFD3466B)
                  : AppColors.textPrimary;
              final statusLabel = actualBleeding
                  ? (isPersian
                        ? 'روز ثبت‌شده خون‌ریزی'
                        : 'Recorded bleeding day')
                  : estimatedBleeding
                  ? (isPersian
                        ? 'روز تخمینی دوره'
                        : 'Estimated period day')
                  : phase == WomenCalendarPhase.prePeriod
                  ? (isPersian
                        ? 'نزدیک دوره تخمینی'
                        : 'Estimated pre-period day')
                  : '';

              return Semantics(
                label: [
                  formatAppDate(context, date),
                  if (statusLabel.isNotEmpty) statusLabel,
                ].join('، '),
                child: Container(
                  decoration: BoxDecoration(
                    color: actualBleeding
                        ? const Color(0xFFFFD2DF)
                        : estimatedBleeding
                        ? const Color(0xFFFFEEF3)
                        : const Color(0xFFF8F9FB),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(
                      color: isToday ? _periodColor : Colors.transparent,
                      width: isToday ? 1.6 : 1,
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
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Container(
                        width: actualBleeding || estimatedBleeding ? 8 : 6,
                        height: actualBleeding || estimatedBleeding ? 8 : 6,
                        decoration: BoxDecoration(
                          color: actualBleeding || estimatedBleeding
                              ? _periodColor
                              : _phaseColor(phase).withValues(alpha: 0.8),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          const _CalendarLegend(),
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
        ? WomenCalendarPhase.period
        : estimate.phase;
    final phaseLabel = recordedToday
        ? 'دوره ثبت‌شده'
        : switch (phase) {
            WomenCalendarPhase.period => 'دوره تخمینی',
            WomenCalendarPhase.postPeriod => 'روزهای پس از دوره',
            WomenCalendarPhase.cycle => 'میانه چرخه',
            WomenCalendarPhase.prePeriod => 'نزدیک دوره بعدی',
          };
    final helperText = recordedToday
        ? 'اطلاعات امروز بر اساس دوره‌ای است که ثبت کرده‌اید.'
        : phase == WomenCalendarPhase.period
        ? 'امروز در بازه تخمینی دوره قرار دارد.'
        : 'شروع دوره بعدی حدود ${localizeDigits(context, estimate.daysUntilNextPeriod)} روز دیگر تخمین زده می‌شود.';

    return Column(
      key: const ValueKey('women-calendar-cycle-ring'),
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final diameter = constraints.maxWidth.clamp(230.0, 330.0);
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
                        cycleDay: estimate.cycleDay,
                        cycleLength: estimate.cycleLength,
                        periodLength: estimate.periodLength,
                        dayLabel: localizeDigits(
                          context,
                          estimate.cycleDay,
                        ),
                      ),
                    ),
                    Center(
                      child: Padding(
                        padding: EdgeInsets.all(diameter * 0.25),
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
                            const SizedBox(height: 10),
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
                                  fontSize: 21,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: _phaseColor(phase).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                'روز ${localizeDigits(context, estimate.cycleDay)} از ${localizeDigits(context, estimate.cycleLength)}',
                                key: const ValueKey(
                                  'women-calendar-cycle-day',
                                ),
                                maxLines: 1,
                                style: TextStyle(
                                  color: _phaseColor(phase),
                                  fontWeight: FontWeight.w800,
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
  const _CycleRingPainter({
    required this.cycleDay,
    required this.cycleLength,
    required this.periodLength,
    required this.dayLabel,
  });

  final int cycleDay;
  final int cycleLength;
  final int periodLength;
  final String dayLabel;

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = size.width * 0.075;
    final rect = Offset.zero & size;
    final ringRect = rect.deflate(strokeWidth * 1.35);
    const startAngle = -math.pi / 2;
    const gap = 0.028;

    final trackPaint = Paint()
      ..color = _cycleTrackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(ringRect, 0, math.pi * 2, false, trackPaint);

    final postDays = math.min(4, math.max(1, cycleLength - periodLength - 6));
    final preDays = math.min(5, math.max(1, cycleLength - periodLength - postDays - 1));
    final cycleDays = math.max(1, cycleLength - periodLength - postDays - preDays);
    final segments = <({int days, Color color})>[
      (days: periodLength, color: _periodColor),
      (days: postDays, color: _postPeriodColor),
      (days: cycleDays, color: _cycleColor),
      (days: preDays, color: _prePeriodColor),
    ];

    var cursor = startAngle;
    for (final segment in segments) {
      final sweep = math.pi * 2 * segment.days / cycleLength;
      final paint = Paint()
        ..color = segment.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        ringRect,
        cursor + gap,
        math.max(0.01, sweep - (gap * 2)),
        false,
        paint,
      );
      cursor += sweep;
    }

    final radius = ringRect.width / 2;
    final center = ringRect.center;
    for (var day = 1; day <= cycleLength; day++) {
      final angle = startAngle + (math.pi * 2 * (day - 0.5) / cycleLength);
      final point = Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      );
      canvas.drawCircle(
        point,
        math.max(1.4, strokeWidth * 0.09),
        Paint()..color = Colors.white.withValues(alpha: 0.9),
      );
    }

    final markerAngle =
        startAngle + (math.pi * 2 * (cycleDay - 0.5) / cycleLength);
    final markerCenter = Offset(
      center.dx + math.cos(markerAngle) * radius,
      center.dy + math.sin(markerAngle) * radius,
    );
    final markerColor = _phaseColorForDay(
      cycleDay: cycleDay,
      cycleLength: cycleLength,
      periodLength: periodLength,
      postDays: postDays,
      preDays: preDays,
    );
    final markerRadius = strokeWidth * 1.08;
    canvas.drawCircle(
      markerCenter.translate(0, 3),
      markerRadius + 3,
      Paint()..color = Colors.black.withValues(alpha: 0.08),
    );
    canvas.drawCircle(markerCenter, markerRadius + 2, Paint()..color = Colors.white);
    canvas.drawCircle(
      markerCenter,
      markerRadius,
      Paint()
        ..color = markerColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    final textPainter = TextPainter(
      text: TextSpan(
        children: [
          const TextSpan(
            text: 'روز\n',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 9,
              height: 1.1,
            ),
          ),
          TextSpan(
            text: dayLabel,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w900,
              height: 1.1,
            ),
          ),
        ],
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.rtl,
    )..layout(maxWidth: markerRadius * 1.7);
    textPainter.paint(
      canvas,
      markerCenter - Offset(textPainter.width / 2, textPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _CycleRingPainter oldDelegate) =>
      oldDelegate.cycleDay != cycleDay ||
      oldDelegate.cycleLength != cycleLength ||
      oldDelegate.periodLength != periodLength ||
      oldDelegate.dayLabel != dayLabel;
}

class _PhaseLegend extends StatelessWidget {
  const _PhaseLegend();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      alignment: WrapAlignment.center,
      spacing: 14,
      runSpacing: 9,
      children: [
        _LegendItem(color: _periodColor, label: 'دوره'),
        _LegendItem(color: _postPeriodColor, label: 'پس از دوره'),
        _LegendItem(color: _cycleColor, label: 'میانه چرخه'),
        _LegendItem(color: _prePeriodColor, label: 'نزدیک دوره'),
      ],
    );
  }
}

class _CalendarLegend extends StatelessWidget {
  const _CalendarLegend();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      alignment: WrapAlignment.center,
      spacing: 14,
      runSpacing: 8,
      children: [
        _LegendItem(color: _periodColor, label: 'ثبت‌شده یا تخمینی'),
        _LegendItem(color: _cycleColor, label: 'میانه چرخه'),
        _LegendItem(color: _prePeriodColor, label: 'نزدیک دوره'),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text(
        label,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

WomenCalendarPhase? _phaseForDate(
  DateTime date,
  WomenCalendarEstimate? estimate,
) {
  if (estimate == null) return null;
  final difference = _dateOnly(date).difference(estimate.cycleStart).inDays;
  final normalized =
      ((difference % estimate.cycleLength) + estimate.cycleLength) %
      estimate.cycleLength;
  final cycleDay = normalized + 1;
  if (cycleDay <= estimate.periodLength) return WomenCalendarPhase.period;
  if (cycleDay <= estimate.periodLength + 4) {
    return WomenCalendarPhase.postPeriod;
  }
  if (estimate.cycleLength - cycleDay < 5) {
    return WomenCalendarPhase.prePeriod;
  }
  return WomenCalendarPhase.cycle;
}

Color _phaseColor(WomenCalendarPhase? phase) => switch (phase) {
  WomenCalendarPhase.period => _periodColor,
  WomenCalendarPhase.postPeriod => _postPeriodColor,
  WomenCalendarPhase.cycle => _cycleColor,
  WomenCalendarPhase.prePeriod => _prePeriodColor,
  null => const Color(0xFFCCD3DA),
};

Color _phaseColorForDay({
  required int cycleDay,
  required int cycleLength,
  required int periodLength,
  required int postDays,
  required int preDays,
}) {
  if (cycleDay <= periodLength) return _periodColor;
  if (cycleDay <= periodLength + postDays) return _postPeriodColor;
  if (cycleDay > cycleLength - preDays) return _prePeriodColor;
  return _cycleColor;
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

bool _sameDay(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;
