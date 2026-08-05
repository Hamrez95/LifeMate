import 'package:flutter/material.dart';
import 'package:shamsi_date/shamsi_date.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../core/theme/app_style.dart';
import '../../core/utils/persian_date_utils.dart';
import '../../core/utils/string_extensions.dart';

class CustomTableCalendar extends StatelessWidget {
  const CustomTableCalendar({
    required this.focusedMonth,
    required this.selectedDate,
    required this.isPersian,
    required this.onDaySelected,
    required this.getDayEventTypes,
    this.onPageChanged,
    super.key,
  });

  final DateTime focusedMonth;
  final DateTime selectedDate;
  final bool isPersian;
  final void Function(DateTime, DateTime) onDaySelected;
  final ValueChanged<DateTime>? onPageChanged;
  final Set<String> Function(DateTime) getDayEventTypes;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(25),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadowDark,
            offset: Offset(5, 5),
            blurRadius: 15,
          ),
          BoxShadow(
            color: AppColors.shadowLight,
            offset: Offset(-5, -5),
            blurRadius: 15,
          ),
        ],
      ),
      child: isPersian
          ? _PersianMonthGrid(
              focusedMonth: focusedMonth,
              selectedDate: selectedDate,
              onDaySelected: onDaySelected,
              onPageChanged: onPageChanged,
              getDayEventTypes: getDayEventTypes,
            )
          : _GregorianCalendar(
              focusedMonth: focusedMonth,
              selectedDate: selectedDate,
              onDaySelected: onDaySelected,
              onPageChanged: onPageChanged,
              getDayEventTypes: getDayEventTypes,
            ),
    );
  }
}

class _PersianMonthGrid extends StatelessWidget {
  const _PersianMonthGrid({
    required this.focusedMonth,
    required this.selectedDate,
    required this.onDaySelected,
    required this.onPageChanged,
    required this.getDayEventTypes,
  });

  final DateTime focusedMonth;
  final DateTime selectedDate;
  final void Function(DateTime, DateTime) onDaySelected;
  final ValueChanged<DateTime>? onPageChanged;
  final Set<String> Function(DateTime) getDayEventTypes;

  static const weekDays = <String>['ش', 'ی', 'د', 'س', 'چ', 'پ', 'ج'];

  DateTime _moveMonth(int delta) {
    final current = Jalali.fromDateTime(focusedMonth);
    var year = current.year;
    var month = current.month + delta;
    if (month < 1) {
      year -= 1;
      month = 12;
    } else if (month > 12) {
      year += 1;
      month = 1;
    }
    return Jalali(year, month, 1).toDateTime();
  }

  @override
  Widget build(BuildContext context) {
    final focused = Jalali.fromDateTime(focusedMonth);
    final firstJalali = Jalali(focused.year, focused.month, 1);
    final firstDate = firstJalali.toDateTime();
    final monthLength = firstJalali.monthLength;
    final leadingEmptyCells = (firstDate.weekday + 1) % 7;

    return Column(
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'ماه قبل',
              onPressed: () => onPageChanged?.call(_moveMonth(-1)),
              icon: const Icon(
                Icons.chevron_right_rounded,
                textDirection: TextDirection.ltr,
              ),
            ),
            Expanded(
              child: Text(
                formatAppMonth(context, focusedMonth),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            IconButton(
              tooltip: 'ماه بعد',
              onPressed: () => onPageChanged?.call(_moveMonth(1)),
              icon: const Icon(
                Icons.chevron_left_rounded,
                textDirection: TextDirection.ltr,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            for (final label in weekDays)
              Expanded(
                child: Center(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: leadingEmptyCells + monthLength,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            childAspectRatio: 0.92,
          ),
          itemBuilder: (context, index) {
            if (index < leadingEmptyCells) return const SizedBox.shrink();
            final day = index - leadingEmptyCells + 1;
            final gregorian = Jalali(
              focused.year,
              focused.month,
              day,
            ).toDateTime();
            return _CalendarCell(
              day: gregorian,
              label: '$day'.toPersianDigit(true),
              selected: _sameDay(gregorian, selectedDate),
              today: _sameDay(gregorian, DateTime.now()),
              eventTypes: getDayEventTypes(gregorian),
              onTap: () => onDaySelected(gregorian, gregorian),
            );
          },
        ),
      ],
    );
  }
}

class _GregorianCalendar extends StatelessWidget {
  const _GregorianCalendar({
    required this.focusedMonth,
    required this.selectedDate,
    required this.onDaySelected,
    required this.onPageChanged,
    required this.getDayEventTypes,
  });

  final DateTime focusedMonth;
  final DateTime selectedDate;
  final void Function(DateTime, DateTime) onDaySelected;
  final ValueChanged<DateTime>? onPageChanged;
  final Set<String> Function(DateTime) getDayEventTypes;

  @override
  Widget build(BuildContext context) {
    return TableCalendar(
      locale: 'en_US',
      firstDay: DateTime.utc(2020, 1, 1),
      lastDay: DateTime.utc(2035, 12, 31),
      focusedDay: focusedMonth,
      calendarFormat: CalendarFormat.month,
      startingDayOfWeek: StartingDayOfWeek.sunday,
      onDaySelected: onDaySelected,
      onPageChanged: onPageChanged,
      selectedDayPredicate: (day) => _sameDay(selectedDate, day),
      headerStyle: const HeaderStyle(
        formatButtonVisible: false,
        titleCentered: true,
      ),
      calendarBuilders: CalendarBuilders(
        defaultBuilder: (context, day, _) => _CalendarCell(
          day: day,
          label: '${day.day}',
          selected: false,
          today: false,
          eventTypes: getDayEventTypes(day),
          onTap: () => onDaySelected(day, day),
        ),
        todayBuilder: (context, day, _) => _CalendarCell(
          day: day,
          label: '${day.day}',
          selected: false,
          today: true,
          eventTypes: getDayEventTypes(day),
          onTap: () => onDaySelected(day, day),
        ),
        selectedBuilder: (context, day, _) => _CalendarCell(
          day: day,
          label: '${day.day}',
          selected: true,
          today: false,
          eventTypes: getDayEventTypes(day),
          onTap: () => onDaySelected(day, day),
        ),
      ),
    );
  }
}

class _CalendarCell extends StatelessWidget {
  const _CalendarCell({
    required this.day,
    required this.label,
    required this.selected,
    required this.today,
    required this.eventTypes,
    required this.onTap,
  });

  final DateTime day;
  final String label;
  final bool selected;
  final bool today;
  final Set<String> eventTypes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isPast = DateTime(
      day.year,
      day.month,
      day.day,
    ).isBefore(DateTime(now.year, now.month, now.day));
    final hasMissed = today && eventTypes.contains('missed');

    return Padding(
      padding: const EdgeInsets.all(3),
      child: Material(
        color: selected ? AppColors.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              border: today && !selected
                  ? Border.all(
                      color: hasMissed ? Colors.orange : AppColors.primary,
                      width: 1.4,
                    )
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: selected
                        ? Colors.white
                        : isPast
                        ? Colors.grey.shade400
                        : AppColors.textPrimary,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                if (eventTypes.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  _EventDots(eventTypes: eventTypes, faded: isPast),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EventDots extends StatelessWidget {
  const _EventDots({required this.eventTypes, required this.faded});

  final Set<String> eventTypes;
  final bool faded;

  @override
  Widget build(BuildContext context) {
    final colors = <Color>[
      if (eventTypes.contains('medicine') || eventTypes.contains('med'))
        AppColors.calDotMedicine,
      if (eventTypes.contains('doctor') || eventTypes.contains('appointment'))
        AppColors.calDotDoctor,
      if (eventTypes.contains('treatment') || eventTypes.contains('injection'))
        AppColors.calDotTreatment,
    ];
    return Opacity(
      opacity: faded ? 0.45 : 1,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final color in colors.take(3))
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              width: 5,
              height: 5,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
        ],
      ),
    );
  }
}

bool _sameDay(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;
