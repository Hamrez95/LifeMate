import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:wellmate/core/theme/app_style.dart';
import 'package:wellmate/providers/medication_provider.dart';
// import 'package:wellmate/services/backend_service.dart';
import '../../localization/app_localizations.dart';
import '../../models/schedule_item_model.dart';
import '../../core/utils/string_extensions.dart';

import 'custom_table_calendar.dart';
import 'schedule_item_card.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({Key? key}) : super(key: key);

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _selectedDate = DateTime.now();
  DateTime _focusedMonth = DateTime.now();

  @override
  void initState() {
    super.initState();
    // در صورت نیاز اگر پرووایدر خودش دیتا رو نمیگیره، اینجا فراخوانی کن
    // Future.microtask(() => context.read<MedicationProvider>().fetchData());
  }

  // متد بررسی گذشته بودن زمان دارو
  bool _isTimePassed(String time, DateTime targetDate) {
    final now = DateTime.now();
    final normalizedTarget =
        DateTime(targetDate.year, targetDate.month, targetDate.day);
    final normalizedNow = DateTime(now.year, now.month, now.day);

    if (normalizedTarget.isBefore(normalizedNow)) return true;
    if (normalizedTarget.isAfter(normalizedNow)) return false;

    // اگر روز انتخاب شده همین امروز است، ساعت‌ها رو مقایسه می‌کنیم
    try {
      final parts = time.split(':');
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1].split(' ')[0]);
      final itemTime = DateTime(now.year, now.month, now.day, hour, minute);
      return now.isAfter(itemTime);
    } catch (e) {
      return false;
    }
  }

  // فیلتر کردن رویدادهای یک روز خاص بر اساس لیست کل داروها
  List<ScheduleItemModel> _getEventsForDay(
      DateTime targetDate, List<ScheduleItemModel> allItems) {
    final filteredItems = allItems.where((item) {
      // اگر startDate null بود، فرض می‌کنیم برای امروز تنظیم شده است
      final start = item.startDate ?? DateTime.now();

      final normalizedTarget =
          DateTime(targetDate.year, targetDate.month, targetDate.day);
      final normalizedStart = DateTime(start.year, start.month, start.day);

      // اگر تاریخ انتخابی قبل از تاریخ شروع رویداد باشد، آن را نشان نده
      if (normalizedTarget.isBefore(normalizedStart)) return false;

      final difference = normalizedTarget.difference(normalizedStart).inDays;

      // ۱. اولویت اول: رویدادهای یک‌باره (مثل ویزیت دکتر یا آزمایش)
      // فقط در صورتی نشان داده می‌شوند که اختلاف روزها دقیقا صفر باشد (همان روز)
      if (item.frequency == 'یکباره' || item.frequency == 'تاریخ مقرر') {
        return difference == 0;
      }
      // ۲. اولویت دوم: رویدادهای روزانه
      else if (item.frequency == 'روزانه') {
        return true;
      }
      // ۳. اولویت سوم: رویدادهای دوره‌ای (چند روز یک‌بار)
      else if (item.intervalDays != null && item.intervalDays! > 1) {
        return difference % item.intervalDays! == 0;
      }

      return false;
    }).toList();

    // مرتب‌سازی بر اساس ساعت
    filteredItems.sort((a, b) => a.time.compareTo(b.time));
    return filteredItems;
  }

  // استخراج نوع رویدادها برای نمایش در تقویم (تیک، علامت تعجب و...)
  Set<String> _getDayEventTypes(
      DateTime day, List<ScheduleItemModel> allItems) {
    final eventsForDay = _getEventsForDay(day, allItems);
    final Set<String> types = {};

    for (var item in eventsForDay) {
      if (item.type != null && item.type!.isNotEmpty) {
        types.add(item.type!);
      } else {
        types.add('med');
      }

      // شرط جدید: فقط اگر نوع رویداد دارو باشد، وضعیت جا مانده بررسی شود
      bool isMedication = (item.type == 'med' ||
          item.type == 'medicine' ||
          item.type == 'default');
      if (isMedication && !item.isDone && _isTimePassed(item.time, day)) {
        types.add('missed');
      }
    }

    return types;
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final isPersian = Localizations.localeOf(context).languageCode == 'fa';

    // گرفتن همه داروها از پرووایدر
    final medicationProvider = context.watch<MedicationProvider>();
    final allItems = medicationProvider.allMedications;

    // فیلتر کردن داروهای مخصوص روز انتخاب شده
    final todayEvents = _getEventsForDay(_selectedDate, allItems);

    final dayFormat =
        DateFormat('d').format(_selectedDate).toPersianDigit(isPersian);
    final monthFormat = isPersian
        ? DateFormat('MMMM', 'fa_IR').format(_selectedDate)
        : DateFormat('MMM').format(_selectedDate);

    final scheduleTitle =
        "${loc['calendar_schedule_for'] ?? 'برنامه روز'} $dayFormat $monthFormat";

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 20, top: 10),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: CustomTableCalendar(
                  focusedMonth: _focusedMonth,
                  selectedDate: _selectedDate,
                  isPersian: isPersian,
                  // پاس دادن توابع به تقویم
                  getDayEventTypes: (day) => _getDayEventTypes(day, allItems),
                  onDaySelected: (selectedDay, focusedDay) {
                    setState(() {
                      _selectedDate = selectedDay;
                      _focusedMonth = focusedDay;
                    });
                  },
                ),
              ),
              const SizedBox(height: 25),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(30)),
                  boxShadow: [
                    BoxShadow(
                        color: AppColors.shadowDark.withOpacity(0.5),
                        blurRadius: 10,
                        offset: const Offset(0, -5))
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(scheduleTitle,
                        style: AppTextStyles.heading(context)
                            .copyWith(fontSize: 18)),
                    const SizedBox(height: 16),
                    todayEvents.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 40),
                            child: Center(
                              child: Text(
                                  loc['calendar_empty'] ?? 'بدون برنامه',
                                  style: AppTextStyles.body(context)),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: todayEvents.length,
                            itemBuilder: (context, index) {
                              final item = todayEvents[index];

                              // تشخیص اینکه آیا روز انتخاب شده در گذشته/امروز است یا آینده
                              final now = DateTime.now();
                              final normalizedSelected = DateTime(
                                  _selectedDate.year,
                                  _selectedDate.month,
                                  _selectedDate.day);
                              final normalizedNow =
                                  DateTime(now.year, now.month, now.day);
                              final isFuture =
                                  normalizedSelected.isAfter(normalizedNow);

                              // تعیین وضعیت فراموش شده
                              bool isMissed = !item.isDone &&
                                  _isTimePassed(item.time, _selectedDate);

                              // تیک خوردن دارو: فقط در صورتی که دارو مصرف شده باشد و روز انتخابی در آینده نباشد
                              bool showDoneMark = item.isDone && !isFuture;

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12.0),
                                child: ScheduleItemCard(
                                  item: item,
                                  loc: loc,
                                  isPersian: isPersian,
                                  isMissed: isMissed,
                                  showDone:
                                      showDoneMark, // <--- ارسال وضعیت تیک به کارت
                                ),
                              );
                            },
                          ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
