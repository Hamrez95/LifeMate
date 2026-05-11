import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:wellmate/core/theme/app_style.dart';
import '../../../core/utils/string_extensions.dart';

class CustomTableCalendar extends StatelessWidget {
  final DateTime focusedMonth;
  final DateTime selectedDate;
  final bool isPersian;
  final Function(DateTime, DateTime) onDaySelected;
  final Set<String> Function(DateTime) getDayEventTypes;

  const CustomTableCalendar({
    Key? key,
    required this.focusedMonth,
    required this.selectedDate,
    required this.isPersian,
    required this.onDaySelected,
    required this.getDayEventTypes,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final font = AppTextStyles.get(context).fontFamily;
    final weekDays = isPersian
        ? ['ش', 'ی', 'د', 'س', 'چ', 'پ', 'ج']
        : ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(25),
        boxShadow: const [
          BoxShadow(
              color: AppColors.shadowDark,
              offset: Offset(5, 5),
              blurRadius: 15),
          BoxShadow(
              color: AppColors.shadowLight,
              offset: Offset(-5, -5),
              blurRadius: 15),
        ],
      ),
      child: TableCalendar(
        locale: isPersian ? 'fa_IR' : 'en_US',
        firstDay: DateTime.utc(2020, 1, 1),
        lastDay: DateTime.utc(2030, 12, 31),
        focusedDay: focusedMonth,
        calendarFormat: CalendarFormat.month,
        startingDayOfWeek:
            isPersian ? StartingDayOfWeek.saturday : StartingDayOfWeek.sunday,
        onDaySelected: onDaySelected,
        selectedDayPredicate: (day) => isSameDay(selectedDate, day),
        headerStyle: HeaderStyle(
          formatButtonVisible: false,
          titleCentered: true,
          titleTextStyle: TextStyle(
              fontFamily: font,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary),
          leftChevronIcon:
              const Icon(Icons.chevron_left, color: AppColors.textPrimary),
          rightChevronIcon:
              const Icon(Icons.chevron_right, color: AppColors.textPrimary),
        ),
        calendarBuilders: CalendarBuilders(
          dowBuilder: (context, day) {
            final dowText = weekDays[day.weekday % 7];
            return Center(
              child: Text(dowText,
                  style: TextStyle(
                      fontFamily: font,
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
            );
          },
          defaultBuilder: (context, day, _) =>
              _buildCalendarCell(day, font, isSelected: false, isToday: false),
          todayBuilder: (context, day, _) =>
              _buildCalendarCell(day, font, isSelected: false, isToday: true),
          selectedBuilder: (context, day, _) =>
              _buildCalendarCell(day, font, isSelected: true, isToday: false),
          outsideBuilder: (context, day, _) => Center(
            child: Text('${day.day}'.toPersianDigit(isPersian),
                style:
                    TextStyle(fontFamily: font, color: Colors.grey.shade300)),
          ),
        ),
      ),
    );
  }

  Widget _buildCalendarCell(DateTime day, String? font,
      {required bool isSelected, required bool isToday}) {
    final eventTypes = getDayEventTypes(day);

    return Container(
      margin: const EdgeInsets.all(4.0),
      alignment: Alignment
          .center, // <-- این خط باعث می‌شود کانتینر تمام عرض سلول را پر کند
      decoration: BoxDecoration(
        color: isSelected ? AppColors.primary : Colors.transparent,
        borderRadius:
            BorderRadius.circular(14.0), // کمی گردتر برای زیبایی بیشتر
        border: isToday && !isSelected
            ? Border.all(color: AppColors.primary, width: 1.5)
            : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '${day.day}'.toPersianDigit(isPersian),
            style: TextStyle(
                fontFamily: font,
                color: isSelected ? Colors.white : AppColors.textPrimary,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
          ),
          if (eventTypes.isNotEmpty) ...[
            const SizedBox(height: 4), // ایجاد فاصله ثابت به جای Spacer
            _buildEventDots(eventTypes),
          ]
        ],
      ),
    );
  }

  Widget _buildEventDots(Set<String> eventTypes) {
    List<Widget> dots = [];
    if (eventTypes.contains('medicine'))
      dots.add(_dot(AppColors.calDotMedicine));
    if (eventTypes.contains('doctor')) dots.add(_dot(AppColors.calDotDoctor));
    if (eventTypes.contains('treatment'))
      dots.add(_dot(AppColors.calDotTreatment));

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
