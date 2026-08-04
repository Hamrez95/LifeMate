import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:shamsi_date/shamsi_date.dart';

import '../../core/theme/app_style.dart';
import '../../core/utils/persian_date_utils.dart';

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
  State<WomenCalendarMonthCard> createState() =>
      _WomenCalendarMonthCardState();
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

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 18,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  formatAppMonth(context, _focusedDate),
                  key: const ValueKey('women-calendar-month-title'),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton(
                tooltip: isPersian ? 'ماه قبل' : 'Previous month',
                onPressed: () => _moveMonth(context, -1),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
              IconButton(
                tooltip: isPersian ? 'ماه بعد' : 'Next month',
                onPressed: () => _moveMonth(context, 1),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
            ],
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
              childAspectRatio: 0.78,
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
                  !actualBleeding &&
                  widget.estimate?.isEstimatedPeriodDay(date) == true;
              final isToday = _sameDay(date, DateTime.now());
              final dayNumber = isPersian
                  ? Jalali.fromDateTime(date).day
                  : date.day;
              final background = actualBleeding
                  ? const Color(0xFFFFD4E6)
                  : estimatedBleeding
                  ? const Color(0xFFF1E8FF)
                  : const Color(0xFFF7F9FB);
              final foreground = actualBleeding
                  ? const Color(0xFFB83672)
                  : estimatedBleeding
                  ? const Color(0xFF7551A8)
                  : AppColors.textPrimary;
              final statusLabel = actualBleeding
                  ? (isPersian
                        ? 'روز ثبت‌شده خون‌ریزی'
                        : 'Recorded bleeding day')
                  : estimatedBleeding
                  ? (isPersian ? 'روز تخمینی دوره' : 'Estimated period day')
                  : '';

              return Semantics(
                label: [
                  formatAppDate(context, date),
                  if (statusLabel.isNotEmpty) statusLabel,
                ].join('، '),
                child: Container(
                  decoration: BoxDecoration(
                    color: background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isToday ? AppColors.primary : Colors.transparent,
                      width: isToday ? 1.5 : 1,
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
                      const SizedBox(height: 4),
                      SizedBox(
                        width: 7,
                        height: 7,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: actualBleeding || estimatedBleeding
                                ? foreground
                                : Colors.transparent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: [
              _LegendItem(
                color: const Color(0xFFFFD4E6),
                label: isPersian ? 'ثبت‌شده' : 'Recorded',
              ),
              _LegendItem(
                color: const Color(0xFFF1E8FF),
                label: isPersian ? 'تخمینی' : 'Estimated',
              ),
            ],
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
      final parsedEnd = DateTime.tryParse(
        episode['endedOn']?.toString() ?? '',
      );
      final end = _dateOnly(parsedEnd ?? today);
      final start = _dateOnly(started);
      if (!day.isBefore(start) && !day.isAfter(end)) return true;
    }
    return false;
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
        width: 12,
        height: 12,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(fontSize: 12)),
    ],
  );
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

bool _sameDay(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;
