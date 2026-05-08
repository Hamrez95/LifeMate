// lib/screens/calendar/calendar_screen.dart

import 'package:caremate/models/user_model.dart';
import 'package:caremate/screens/calendar/calendar_view.dart';
import 'package:caremate/screens/calendar/schedule_card.dart';
import 'package:caremate/screens/calendar/user_selector.dart';
import 'package:caremate/screens/dashboard_screen.dart';
import 'package:caremate/widgets/caremate_bottom_nav.dart';
import 'package:caremate/widgets/custom_app_header.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/localization/locale_provider.dart';
import '../../core/utils/string_extensions.dart';
import '../../models/event_model.dart';
import '../../data/app_mock_data.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({Key? key}) : super(key: key);

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  // 1. انتخاب خودکار امروز: مقدار اولیه _selectedDate همین الان DateTime.now() است.
  DateTime _selectedDate = DateTime.now();
  DateTime _focusedMonth = DateTime.now();
  late String _selectedUserId;

  @override
  void initState() {
    super.initState();
    // انتخاب اولین کاربر به عنوان پیش‌فرض
    if (AppMockData.familyMembers.isNotEmpty) {
      _selectedUserId = AppMockData.familyMembers.first.id;
    }
  }

  // --- توابع مدیریت State ---

  /// تاریخ را نرمال می‌کند (ساعت، دقیقه و ثانیه را صفر می‌کند) تا مقایسه‌ها دقیق باشد
  DateTime _normalizeDate(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  /// لیست رویدادهای یک روز خاص برای کاربر انتخاب‌شده را برمی‌گرداند
  List<EventModel> _getEventsForDayAndUser(DateTime day) {
    final normalizedDay = _normalizeDate(day);
    return AppMockData.calendarEvents.where((event) {
      return _normalizeDate(event.date) == normalizedDay &&
          event.userId == _selectedUserId;
    }).toList();
  }

  // --- توابع جدید برای منطق پیشرفته تقویم ---

  /// [جدید] بررسی می‌کند که آیا در یک روز گذشته، رویداد انجام‌نشده وجود دارد یا خیر.
  /// این تابع به CalendarView ارسال می‌شود تا پس‌زمینه قرمز را اعمال کند.
  bool _hasOverdueEvents(DateTime day) {
    final today = _normalizeDate(DateTime.now());
    // فقط روزهای قبل از امروز را بررسی کن
    if (day.isBefore(today)) {
      return AppMockData.calendarEvents.any((event) =>
          _normalizeDate(event.date) == _normalizeDate(day) &&
          event.userId == _selectedUserId &&
          event.isCompleted == false);
    }
    return false;
  }

  /// [جدید] یک مجموعه (Set) از انواع رویدادهای موجود در یک روز را برمی‌گرداند.
  /// استفاده از Set از نمایش نقاط تکراری جلوگیری می‌کند.
  Set<EventType> _getDayEventTypes(DateTime day) {
    final events = _getEventsForDayAndUser(day);
    return events.map((event) => event.type).toSet();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final font = Theme.of(context).textTheme.bodyMedium?.fontFamily ??
        (isRtl ? 'Vazir' : 'Nunito');

    // پیدا کردن اطلاعات کاربر انتخاب‌شده
    final selectedUser = AppMockData.familyMembers.firstWhere(
      (user) => user.id == _selectedUserId,
      orElse: () => AppMockData.familyMembers.first,
    );

    // دریافت رویدادهای روز انتخاب‌شده
    final eventsForSelectedDay = _getEventsForDayAndUser(_selectedDate);
    final monthNamesEn = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    final monthNamesFa = [
      'ژانویه',
      'فوریه',
      'مارس',
      'آوریل',
      'مه',
      'ژوئن',
      'ژوئیه',
      'اوت',
      'سپتامبر',
      'اکتبر',
      'نوامبر',
      'دسامبر'
    ];
    final monthName = isRtl
        ? monthNamesFa[_selectedDate.month - 1]
        : monthNamesEn[_selectedDate.month - 1];
    return Scaffold(
        body: SafeArea(
          bottom: false, // دقیقاً مثل داشبورد
          child: Padding(
            // اعمال همان فاصله‌های داشبورد برای یکسان‌سازی
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              children: [
                // --- Header ---
                const CustomAppHeader(),

                const SizedBox(height: 16),
                UserSelector(
                  selectedUserId: _selectedUserId,
                  font: TextStyle(fontFamily: font),
                  onUserSelected: (userId) {
                    setState(() {
                      _selectedUserId = userId;
                    });
                  },
                ),
                const SizedBox(height: 16),
                // ویجت تقویم با منطق جدید
                CalendarView(
                  focusedMonth: _focusedMonth,
                  selectedDate: _selectedDate,
                  onDaySelected: (selectedDay, focusedDay) {
                    setState(() {
                      _selectedDate = selectedDay;
                      _focusedMonth = focusedDay;
                    });
                  },
                  onPageChanged: (focusedDay) {
                    setState(() {
                      _focusedMonth = focusedDay;
                    });
                  },
                  // پاس دادن توابع جدید به ویجت نمایش
                  getDayEventTypes: _getDayEventTypes,
                  hasOverdueEvents: _hasOverdueEvents,
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        loc['cal_schedule'],
                        style: TextStyle(
                            fontFamily: font,
                            fontSize: 18,
                            fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${_selectedDate.day} $monthName, ${_selectedDate.year}'
                            .toPersianDigit(isRtl),
                        style: TextStyle(
                          fontFamily: font,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: eventsForSelectedDay.isEmpty
                      ? Center(
                          child: Text(
                            loc['no_events_today'],
                            style: TextStyle(
                                fontFamily: font,
                                color: const Color.fromARGB(255, 88, 88, 88)),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          itemCount: eventsForSelectedDay.length,
                          itemBuilder: (context, index) {
                            return Padding(
                                padding: const EdgeInsets.only(
                                    bottom:
                                        12.0), // ایجاد فاصله ۱۲ پیکسلی در پایین هر کارت
                                child: ScheduleCard(
                                  event: eventsForSelectedDay[index],
                                  font: TextStyle(
                                      fontFamily: font), // <--- تغییر اینجاست
                                  isPersian: isRtl,
                                ));
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
        bottomNavigationBar: CareMateBottomNav(
            currentIndex: 0, // 👈 در نویگیشن بار شما، عدد ۰ مربوط به تقویم است
            onTap: (index) {
              // اگر کاربر روی همون آیکون تقویم کلیک کرد، نیازی نیست کاری انجام بدیم
              if (index == 0) return;

              if (index == 4) {
                // 👈 ایندکس ۴ برای خانه (داشبورد)
                Navigator.pushReplacement(
                  context,
                  PageRouteBuilder(
                    // نام کلاس صفحه اصلی (داشبورد) خود را اینجا جایگزین کنید، مثلا DashboardScreen()
                    pageBuilder: (_, __, ___) =>
                        const DashboardScreen(), // 👈 نام کلاس خانه
                    transitionDuration: Duration.zero,
                    reverseTransitionDuration: Duration.zero,
                  ),
                );
              } else if (index == 1) {
                // 👈 ایندکس ۱ برای چت
                // اگر کلاس صفحه چت را دارید، می‌توانید به همین شکل اضافه‌اش کنید
                // Navigator.pushReplacement(...)
              }
            }));
  }
}
