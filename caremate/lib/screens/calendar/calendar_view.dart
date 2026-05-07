import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/string_extensions.dart';

class CalendarView extends StatelessWidget {
  final DateTime focusedMonth;
  final DateTime selectedDate;
  final bool isPersian;
  final TextStyle font;
  final Function(int) onMonthChanged;
  final Function(DateTime) onDaySelected;
  final bool Function(DateTime) hasEventForUser; // تابعی برای چک کردن رویداد

  const CalendarView({
    Key? key,
    required this.focusedMonth,
    required this.selectedDate,
    required this.isPersian,
    required this.font,
    required this.onMonthChanged,
    required this.onDaySelected,
    required this.hasEventForUser,
  }) : super(key: key);

  DateTime _normalizeDate(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  @override
  Widget build(BuildContext context) {
    final daysInMonth =
        DateUtils.getDaysInMonth(focusedMonth.year, focusedMonth.month);
    final firstDayOfMonth = DateTime(focusedMonth.year, focusedMonth.month, 1);
    final weekDayOffset = firstDayOfMonth.weekday % 7;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration:
          AppColors.softDecoration(color: Colors.white.withOpacity(0.85)),
      child: Column(
        children: [
          // هدر تقویم (انتخاب ماه)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Icon(Icons.calendar_month,
                  color: AppColors.primaryText, size: 20),
              Row(
                children: [
                  IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: () => onMonthChanged(-1),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints()),
                  const SizedBox(width: 10),
                  Text(
                      DateFormat('MMMM yyyy')
                          .format(focusedMonth)
                          .toPersianDigit(isPersian),
                      style: font.copyWith(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 10),
                  IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: () => onMonthChanged(1),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints()),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          // روزهای هفته
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: ['S', 'M', 'T', 'W', 'T', 'F', 'S']
                .map((d) => SizedBox(
                      width: 30,
                      child: Center(
                          child: Text(d,
                              style: font.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey[600]))),
                    ))
                .toList(),
          ),
          const SizedBox(height: 10),
          // گرید روزها
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: daysInMonth + weekDayOffset,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7, mainAxisSpacing: 8, crossAxisSpacing: 8),
            itemBuilder: (context, index) {
              if (index < weekDayOffset) return const SizedBox();

              final dayNum = index - weekDayOffset + 1;
              final currentDayDate =
                  DateTime(focusedMonth.year, focusedMonth.month, dayNum);
              final isSelected = _normalizeDate(selectedDate) == currentDayDate;
              final hasEvent = hasEventForUser(currentDayDate);

              return GestureDetector(
                onTap: () => onDaySelected(currentDayDate),
                child: Container(
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.darkBlue : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$dayNum'.toPersianDigit(isPersian),
                        style: font.copyWith(
                          color:
                              isSelected ? Colors.white : AppColors.primaryText,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      if (hasEvent && !isSelected) ...[
                        const SizedBox(height: 4),
                        Container(
                            width: 5,
                            height: 5,
                            decoration: const BoxDecoration(
                                color: Colors.pinkAccent,
                                shape: BoxShape.circle)),
                      ]
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
