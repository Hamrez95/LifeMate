import 'package:flutter/material.dart';
import 'package:shamsi_date/shamsi_date.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/persian_date_utils.dart';
import '../../core/utils/string_extensions.dart';
import '../../models/event_model.dart';
import 'package:lifemate_client/lifemate_client.dart';

typedef GetEventTypesCallback = Set<EventType> Function(DateTime day);
typedef HasOverdueEventsCallback = bool Function(DateTime day);

class CalendarView extends StatelessWidget {
  const CalendarView({
    super.key,
    required this.focusedMonth,
    required this.selectedDate,
    required this.onDaySelected,
    required this.onPageChanged,
    required this.getDayEventTypes,
    required this.hasOverdueEvents,
  });

  final DateTime focusedMonth;
  final DateTime selectedDate;
  final void Function(DateTime, DateTime) onDaySelected;
  final ValueChanged<DateTime> onPageChanged;
  final GetEventTypesCallback getDayEventTypes;
  final HasOverdueEventsCallback hasOverdueEvents;

  @override
  Widget build(BuildContext context) {
    final isPersian = usesPersianCalendar(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: isPersian
          ? _PersianCalendar(
              focusedMonth: focusedMonth,
              selectedDate: selectedDate,
              onDaySelected: onDaySelected,
              onPageChanged: onPageChanged,
              getDayEventTypes: getDayEventTypes,
              hasOverdueEvents: hasOverdueEvents,
            )
          : _GregorianCalendar(
              focusedMonth: focusedMonth,
              selectedDate: selectedDate,
              onDaySelected: onDaySelected,
              onPageChanged: onPageChanged,
              getDayEventTypes: getDayEventTypes,
              hasOverdueEvents: hasOverdueEvents,
            ),
    );
  }
}

class _PersianCalendar extends StatelessWidget {
  const _PersianCalendar({
    required this.focusedMonth,
    required this.selectedDate,
    required this.onDaySelected,
    required this.onPageChanged,
    required this.getDayEventTypes,
    required this.hasOverdueEvents,
  });

  final DateTime focusedMonth;
  final DateTime selectedDate;
  final void Function(DateTime, DateTime) onDaySelected;
  final ValueChanged<DateTime> onPageChanged;
  final GetEventTypesCallback getDayEventTypes;
  final HasOverdueEventsCallback hasOverdueEvents;

  static final _weekDays = <String>[
    LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'ش', en: "Sat"),
      en: "Sat",
    ),
    LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'ی', en: "Sun"),
      en: "Sun",
    ),
    LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'د', en: "Mon"),
      en: "Mon",
    ),
    LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'س', en: "Tue"),
      en: "Tue",
    ),
    LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'چ', en: "Wed"),
      en: "Wed",
    ),
    LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'پ', en: "Thu"),
      en: "Thu",
    ),
    LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'ج', en: "Fri"),
      en: "Fri",
    ),
  ];

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
    final first = Jalali(focused.year, focused.month, 1);
    final firstDate = first.toDateTime();
    final leadingCells = (firstDate.weekday + 1) % 7;
    final today = _dateOnly(DateTime.now());

    return Column(
      children: [
        Directionality(
          textDirection: LifeMateRuntimeLocale.isPersian
              ? TextDirection.rtl
              : TextDirection.ltr,
          child: Row(
            children: [
              IconButton(
                key: ValueKey('caremate-previous-month'),
                tooltip: LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'ماه قبل',
                    en: "the previous month",
                  ),
                  en: "the previous month",
                ),
                onPressed: () => onPageChanged(_moveMonth(-1)),
                icon: Icon(
                  Icons.chevron_right_rounded,
                  textDirection: TextDirection.ltr,
                ),
              ),
              Expanded(
                child: Text(
                  formatAppMonth(context, focusedMonth),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Vazir',
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                key: ValueKey('caremate-next-month'),
                tooltip: LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'ماه بعد',
                    en: "next month",
                  ),
                  en: "next month",
                ),
                onPressed: () => onPageChanged(_moveMonth(1)),
                icon: Icon(
                  Icons.chevron_left_rounded,
                  textDirection: TextDirection.ltr,
                ),
              ),
            ],
          ),
        ),
        Row(
          children: [
            for (final label in _weekDays)
              Expanded(
                child: Center(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontFamily: 'Vazir',
                      color: Colors.grey.shade600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
          ],
        ),
        SizedBox(height: 6),
        GridView.builder(
          shrinkWrap: true,
          physics: NeverScrollableScrollPhysics(),
          itemCount: leadingCells + first.monthLength,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisExtent: 42,
          ),
          itemBuilder: (context, index) {
            if (index < leadingCells) return SizedBox.shrink();
            final dayNumber = index - leadingCells + 1;
            final day = Jalali(
              focused.year,
              focused.month,
              dayNumber,
            ).toDateTime();
            return _CalendarCell(
              day: day,
              label: '$dayNumber'.toPersianDigit(true),
              eventTypes: getDayEventTypes(day),
              isPastDay: _dateOnly(day).isBefore(today),
              isOverdue: hasOverdueEvents(day),
              isSelected: _sameDay(day, selectedDate),
              isToday: _sameDay(day, today),
              isPersian: true,
              onTap: () => onDaySelected(day, day),
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
    required this.hasOverdueEvents,
  });

  final DateTime focusedMonth;
  final DateTime selectedDate;
  final void Function(DateTime, DateTime) onDaySelected;
  final ValueChanged<DateTime> onPageChanged;
  final GetEventTypesCallback getDayEventTypes;
  final HasOverdueEventsCallback hasOverdueEvents;

  @override
  Widget build(BuildContext context) {
    final today = _dateOnly(DateTime.now());
    return TableCalendar(
      locale: 'en_US',
      firstDay: DateTime.utc(2020, 1, 1),
      lastDay: DateTime.utc(2035, 12, 31),
      focusedDay: focusedMonth,
      currentDay: DateTime.now(),
      calendarFormat: CalendarFormat.month,
      startingDayOfWeek: StartingDayOfWeek.sunday,
      onDaySelected: onDaySelected,
      onPageChanged: onPageChanged,
      selectedDayPredicate: (day) => _sameDay(selectedDate, day),
      headerStyle: HeaderStyle(
        formatButtonVisible: false,
        titleCentered: true,
        leftChevronIcon: Icon(
          Icons.chevron_left_rounded,
          color: Colors.grey.shade700,
        ),
        rightChevronIcon: Icon(
          Icons.chevron_right_rounded,
          color: Colors.grey.shade700,
        ),
      ),
      calendarBuilders: CalendarBuilders(
        defaultBuilder: (context, day, _) => _CalendarCell(
          day: day,
          label: '${day.day}',
          eventTypes: getDayEventTypes(day),
          isPastDay: _dateOnly(day).isBefore(today),
          isOverdue: hasOverdueEvents(day),
          isSelected: false,
          isToday: false,
          isPersian: false,
          onTap: () => onDaySelected(day, day),
        ),
        todayBuilder: (context, day, _) => _CalendarCell(
          day: day,
          label: '${day.day}',
          eventTypes: getDayEventTypes(day),
          isPastDay: false,
          isOverdue: false,
          isSelected: _sameDay(day, selectedDate),
          isToday: true,
          isPersian: false,
          onTap: () => onDaySelected(day, day),
        ),
        selectedBuilder: (context, day, _) => _CalendarCell(
          day: day,
          label: '${day.day}',
          eventTypes: getDayEventTypes(day),
          isPastDay: _dateOnly(day).isBefore(today),
          isOverdue: hasOverdueEvents(day),
          isSelected: true,
          isToday: _sameDay(day, today),
          isPersian: false,
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
    required this.eventTypes,
    required this.isPastDay,
    required this.isOverdue,
    required this.isSelected,
    required this.isToday,
    required this.isPersian,
    required this.onTap,
  });

  final DateTime day;
  final String label;
  final Set<EventType> eventTypes;
  final bool isPastDay;
  final bool isOverdue;
  final bool isSelected;
  final bool isToday;
  final bool isPersian;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textColor = isSelected
        ? Colors.white
        : isPastDay
        ? const Color(0xFF666666)
        : Colors.black;
    return Padding(
      padding: const EdgeInsets.all(3),
      child: Material(
        color: isSelected
            ? AppColors.CalPrimary
            : isOverdue
            ? AppColors.CalBackForgotten
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: isToday && !isSelected
                  ? Border.all(color: AppColors.CalPrimary, width: 1.5)
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 2),
                Text(
                  label.toPersianDigit(isPersian),
                  style: TextStyle(
                    fontFamily: isPersian ? 'Vazir' : 'Nunito',
                    color: textColor,
                  ),
                ),
                const Spacer(),
                if (eventTypes.isNotEmpty) _EventDots(eventTypes: eventTypes),
                const Spacer(flex: 2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EventDots extends StatelessWidget {
  const _EventDots({required this.eventTypes});

  final Set<EventType> eventTypes;

  @override
  Widget build(BuildContext context) {
    final colors = <Color>[
      if (eventTypes.contains(EventType.medicine)) AppColors.CalFisrtDot,
      if (eventTypes.contains(EventType.appointment) ||
          eventTypes.contains(EventType.doctor))
        AppColors.CalSecondDot,
      if (eventTypes.contains(EventType.injection) ||
          eventTypes.contains(EventType.checkup))
        Colors.orangeAccent,
    ];
    return Row(
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
    );
  }
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

bool _sameDay(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;
