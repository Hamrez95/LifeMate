import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/string_extensions.dart';
import '../../models/event_model.dart';

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
  final Function(DateTime, DateTime) onDaySelected;
  final Function(DateTime) onPageChanged;
  final GetEventTypesCallback getDayEventTypes;
  final HasOverdueEventsCallback hasOverdueEvents;

  @override
  Widget build(BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final font = Theme.of(context).textTheme.bodyMedium?.fontFamily ??
        (isRtl ? 'Vazir' : 'Nunito');
    final weekDays = isRtl
        ? ['ش', 'ی', 'د', 'س', 'چ', 'پ', 'ج']
        : ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    final today = _normalizeDate(DateTime.now());

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TableCalendar(
        locale: isRtl ? 'fa_IR' : 'en_US',
        firstDay: DateTime.utc(2020, 1, 1),
        lastDay: DateTime.utc(2030, 12, 31),
        focusedDay: focusedMonth,
        currentDay: DateTime.now(),
        calendarFormat: CalendarFormat.month,
        startingDayOfWeek:
            isRtl ? StartingDayOfWeek.saturday : StartingDayOfWeek.sunday,
        onDaySelected: onDaySelected,
        onPageChanged: onPageChanged,
        selectedDayPredicate: (day) => isSameDay(selectedDate, day),
        headerStyle: HeaderStyle(
          formatButtonVisible: false,
          titleCentered: true,
          titleTextStyle: TextStyle(
            fontFamily: font,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
          leftChevronIcon:
              Icon(Icons.chevron_left, color: Colors.grey.shade700),
          rightChevronIcon:
              Icon(Icons.chevron_right, color: Colors.grey.shade700),
        ),
        calendarBuilders: CalendarBuilders(
          dowBuilder: (context, day) {
            final text = weekDays[day.weekday % 7];
            return Center(
              child: Text(
                text,
                style: TextStyle(
                  fontFamily: font,
                  color: Colors.grey.shade600,
                  fontSize: 12,
                ),
              ),
            );
          },
          defaultBuilder: (context, day, focusedDay) => _buildCalendarCell(
            day: day,
            eventTypes: getDayEventTypes(day),
            isPastDay: day.isBefore(today),
            isOverdue: hasOverdueEvents(day),
            isSelected: false,
            font: font,
            isRtl: isRtl,
          ),
          todayBuilder: (context, day, focusedDay) => _buildCalendarCell(
            day: day,
            eventTypes: getDayEventTypes(day),
            isPastDay: false,
            isOverdue: false,
            isSelected: isSameDay(day, selectedDate),
            isToday: true,
            font: font,
            isRtl: isRtl,
          ),
          selectedBuilder: (context, day, focusedDay) => _buildCalendarCell(
            day: day,
            eventTypes: getDayEventTypes(day),
            isPastDay: day.isBefore(today),
            isOverdue: hasOverdueEvents(day),
            isSelected: true,
            font: font,
            isRtl: isRtl,
          ),
          outsideBuilder: (context, day, focusedDay) => Center(
            child: Text(
              '${day.day}'.toPersianDigit(isRtl),
              style: TextStyle(
                fontFamily: font,
                color: Colors.grey.shade300,
              ),
            ),
          ),
        ),
      ),
    );
  }

  static DateTime _normalizeDate(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  Widget _buildCalendarCell({
    required DateTime day,
    required Set<EventType> eventTypes,
    required bool isPastDay,
    required bool isOverdue,
    required bool isSelected,
    bool isToday = false,
    required String font,
    required bool isRtl,
  }) {
    final cellColor =
        isOverdue ? AppColors.CalBackForgotten : Colors.transparent;
    final textColor = (isPastDay && !isSelected)
        ? const Color.fromARGB(255, 80, 80, 80)
        : Colors.black;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: cellColor,
        borderRadius: BorderRadius.circular(8),
        border: isToday && !isSelected
            ? Border.all(color: AppColors.CalPrimary, width: 1.5)
            : null,
      ),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: isSelected ? AppColors.CalPrimary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(flex: 2),
            Text(
              '${day.day}'.toPersianDigit(isRtl),
              style: TextStyle(
                fontFamily: font,
                color: isSelected ? Colors.white : textColor,
              ),
            ),
            const Spacer(),
            if (eventTypes.isNotEmpty) _buildEventDots(eventTypes),
            const Spacer(flex: 2),
          ],
        ),
      ),
    );
  }

  Widget _buildEventDots(Set<EventType> eventTypes) {
    final dots = <Widget>[];
    if (eventTypes.contains(EventType.medicine)) {
      dots.add(_dot(AppColors.CalFisrtDot));
    }
    if (eventTypes.contains(EventType.appointment) ||
        eventTypes.contains(EventType.doctor)) {
      dots.add(_dot(AppColors.CalSecondDot));
    }
    if (eventTypes.contains(EventType.injection) ||
        eventTypes.contains(EventType.checkup)) {
      dots.add(_dot(Colors.orangeAccent));
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: dots.take(3).toList(),
    );
  }

  Widget _dot(Color color) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 1.5),
      width: 5,
      height: 5,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
