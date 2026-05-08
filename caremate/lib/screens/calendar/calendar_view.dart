// lib/screens/calendar/calendar_view.dart

import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/localization/locale_provider.dart';
import '../../models/event_model.dart';
import '../../core/utils/string_extensions.dart';

// تعریف یک تایپ جدید برای خوانایی بهتر کد
typedef GetEventTypesCallback = Set<EventType> Function(DateTime day);
typedef HasOverdueEventsCallback = bool Function(DateTime day);

class CalendarView extends StatelessWidget {
  final DateTime focusedMonth;
  final DateTime selectedDate;
  final Function(DateTime, DateTime) onDaySelected;
  final Function(DateTime) onPageChanged;
  final GetEventTypesCallback getDayEventTypes;
  final HasOverdueEventsCallback hasOverdueEvents;

  const CalendarView({
    Key? key,
    required this.focusedMonth,
    required this.selectedDate,
    required this.onDaySelected,
    required this.onPageChanged,
    required this.getDayEventTypes,
    required this.hasOverdueEvents,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final font = Theme.of(context).textTheme.bodyMedium?.fontFamily ??
        (isRtl ? 'Vazir' : 'Nunito');

    // 5. فارسی‌سازی روزهای هفته
    final weekDays = isRtl
        ? ['ش', 'ی', 'د', 'س', 'چ', 'پ', 'ج']
        : ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

    DateTime normalizeDate(DateTime date) {
      return DateTime(date.year, date.month, date.day);
    }

    // تاریخ امروز برای مقایسه
    final today = normalizeDate(DateTime.now());

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: TableCalendar(
        locale: isRtl ? 'fa_IR' : 'en_US',
        firstDay: DateTime.utc(2020, 1, 1),
        lastDay: DateTime.utc(2030, 12, 31),
        focusedDay: focusedMonth,
        currentDay: DateTime.now(), // برای اینکه todayBuilder کار کنه
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
              fontFamily: font, fontSize: 16, fontWeight: FontWeight.bold),
          leftChevronIcon:
              Icon(Icons.chevron_left, color: Colors.grey.shade700),
          rightChevronIcon:
              Icon(Icons.chevron_right, color: Colors.grey.shade700),
        ),
        // --- بخش اصلی تغییرات ظاهری ---
        calendarBuilders: CalendarBuilders(
          // 5. استایل حروف روزهای هفته
          dowBuilder: (context, day) {
            // این محاسبه برای نمایش صحیح روزهای هفته در حالت فارسی و انگلیسی است
            final dowText = isRtl
                ? weekDays[(day.weekday % 7)] // شنبه -> 6+1=7 -> 7%7 = 0
                : weekDays[day.weekday % 7]; // یکشنبه -> 7 -> 7%7 = 0

            return Center(
              child: Text(
                dowText,
                style: TextStyle(
                    fontFamily: font,
                    color: Colors.grey.shade600,
                    fontSize: 12),
              ),
            );
          },

          // استایل سلول‌های عادی تقویم
          defaultBuilder: (context, day, focusedDay) {
            return _buildCalendarCell(
              day: day,
              eventTypes: getDayEventTypes(day),
              isPastDay: day.isBefore(today),
              isOverdue: hasOverdueEvents(day),
              isSelected: false,
              font: font,
              isRtl: isRtl,
            );
          },
          // استایل سلول امروز
          todayBuilder: (context, day, focusedDay) {
            return _buildCalendarCell(
              day: day,
              eventTypes: getDayEventTypes(day),
              isPastDay: false, // امروز گذشته نیست
              isOverdue: false, // رویداد امروز هنوز "فراموش شده" محسوب نمیشه
              isSelected: isSameDay(day, selectedDate),
              isToday: true,
              font: font,
              isRtl: isRtl,
            );
          },
          // استایل سلول انتخاب شده
          selectedBuilder: (context, day, focusedDay) {
            return _buildCalendarCell(
              day: day,
              eventTypes: getDayEventTypes(day),
              isPastDay: day.isBefore(today),
              isOverdue: hasOverdueEvents(day),
              isSelected: true,
              font: font,
              isRtl: isRtl,
            );
          },
          // استایل روزهای خارج از ماه جاری
          outsideBuilder: (context, day, focusedDay) {
            return Center(
              child: Text(
                '${day.day}'.toPersianDigit(isRtl),
                style: TextStyle(fontFamily: font, color: Colors.grey.shade300),
              ),
            );
          },
        ),
      ),
    );
  }

  /// [کامل شد] یک ویجت کمکی برای ساختن هر سلول از تقویم
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
    // 4. هایلایت روزهای فراموش‌شده: اگر isOverdue بود پس‌زمینه قرمز خیلی کمرنگ بده
    final cellColor =
        isOverdue ? AppColors.CalBackForgotten : Colors.transparent;

    // 2. رنگ‌بندی روزهای گذشته: اگر روز در گذشته بود و انتخاب نشده بود، رنگ متن رو خاکستری کن
    final textColor = (isPastDay && !isSelected)
        ? const Color.fromARGB(255, 80, 80, 80)
        : Colors.black;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.all(4.0),
      decoration: BoxDecoration(
        color: cellColor, // رنگ پس‌زمینه برای روزهای فراموش شده
        borderRadius: BorderRadius.circular(8.0),
        border: isToday && !isSelected
            ? Border.all(color: AppColors.CalPrimary, width: 1.5)
            : null,
        shape: BoxShape.rectangle,
      ),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: isSelected ? AppColors.CalPrimary : Colors.transparent,
          borderRadius: BorderRadius.circular(8.0),
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
            const Spacer(flex: 1),
            // 3. نمایش نقاط رنگی هوشمند
            if (eventTypes.isNotEmpty) _buildEventDots(eventTypes),
            const Spacer(flex: 2),
          ],
        ),
      ),
    );
  }

  /// ویجت کمکی برای ساختن نقاط رنگی زیر هر روز
  Widget _buildEventDots(Set<EventType> eventTypes) {
    List<Widget> dots = [];

    // اگر رویداد دارو وجود داشت، نقطه صورتی اضافه کن
    if (eventTypes.contains(EventType.medicine)) {
      dots.add(_dot(AppColors.CalFisrtDot));
    }

    // اگر رویداد دکتر یا چکاپ وجود داشت، نقطه کهربایی اضافه کن
    if (eventTypes.contains(EventType.doctor) ||
        eventTypes.contains(EventType.checkup)) {
      dots.add(_dot(AppColors.CalSecondDot));
    }

    // فقط دو نقطه اول را نمایش بده تا فضا شلوغ نشود
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: dots.take(2).toList(),
    );
  }

  /// ویجت یک نقطه رنگی
  Widget _dot(Color color) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 1.5),
      width: 5,
      height: 5,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}
