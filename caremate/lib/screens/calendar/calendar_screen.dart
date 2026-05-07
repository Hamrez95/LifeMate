import 'package:caremate/screens/calendar/calendar_view.dart';
import 'package:caremate/screens/calendar/schedule_card.dart';
import 'package:caremate/screens/calendar/user_selector.dart';
import 'package:caremate/screens/dashboard_screen.dart';
import 'package:caremate/widgets/caremate_bottom_nav.dart';
import 'package:caremate/widgets/custom_app_header.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

// ایمپورت ویجت‌های جدا شده

import '../../core/localization/app_localizations.dart';
import '../../core/localization/locale_provider.dart';
import '../../core/utils/string_extensions.dart';
import '../../core/constants/app_colors.dart';
import '../../models/event_model.dart';
import '../../data/app_mock_data.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({Key? key}) : super(key: key);

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _selectedDate = DateTime.now();
  DateTime _focusedMonth = DateTime.now();
  late String _selectedUserId;

  @override
  void initState() {
    super.initState();
    if (AppMockData.familyMembers.isNotEmpty) {
      _selectedUserId = AppMockData.familyMembers.first.id;
    }
  }

  // --- توابع مدیریت State ---
  DateTime _normalizeDate(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  List<EventModel> _getEventsForDayAndUser(DateTime day, String userId) {
    return AppMockData.calendarEvents.where((event) {
      return _normalizeDate(event.date) == _normalizeDate(day) &&
          event.userId == userId;
    }).toList();
  }

  bool _hasEventForUser(DateTime day) {
    return AppMockData.calendarEvents.any((event) =>
        _normalizeDate(event.date) == _normalizeDate(day) &&
        event.userId == _selectedUserId);
  }

  void _onDaySelected(DateTime day) {
    setState(() => _selectedDate = day);
  }

  void _onUserSelected(String userId) {
    setState(() => _selectedUserId = userId);
  }

  void _changeMonth(int offset) {
    setState(() {
      _focusedMonth =
          DateTime(_focusedMonth.year, _focusedMonth.month + offset);
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final localeProvider = Provider.of<LocaleProvider>(context);
    final isPersian = localeProvider.locale.languageCode == 'fa';
    final TextStyle mainFont = isPersian
        ? const TextStyle(fontFamily: 'Vazir', color: AppColors.primaryText)
        : const TextStyle(fontFamily: 'Nunito', color: AppColors.primaryText);

    final events = _getEventsForDayAndUser(_selectedDate, _selectedUserId);
    final dayFormat = DateFormat('d').format(_selectedDate);
    final scheduleTitle =
        "${loc['calendar_schedule_for'] ?? 'Schedule for'} $dayFormat${isPersian ? '' : 'th'}"
            .toPersianDigit(isPersian);

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: true,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 20, 24, 10),
              child: CustomAppHeader(),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  loc['calendar_title'] ?? 'Calendar',
                  style: isPersian
                      ? const TextStyle(
                          fontFamily: 'Vazir',
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppColors.darkBlue)
                      : const TextStyle(
                          fontFamily: 'Nunito',
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppColors.darkBlue),
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 120),
                child: Column(
                  children: [
                    const SizedBox(height: 5),

                    // <<< استفاده از ویجت UserSelector >>>
                    UserSelector(
                      selectedUserId: _selectedUserId,
                      font: mainFont,
                      onUserSelected: _onUserSelected,
                    ),
                    const SizedBox(height: 20),

                    // <<< استفاده از ویجت CalendarView >>>
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: CalendarView(
                        focusedMonth: _focusedMonth,
                        selectedDate: _selectedDate,
                        isPersian: isPersian,
                        font: mainFont,
                        onMonthChanged: _changeMonth,
                        onDaySelected: _onDaySelected,
                        hasEventForUser: _hasEventForUser,
                      ),
                    ),
                    const SizedBox(height: 25),

                    // کانتینر لیست برنامه‌ها
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 24),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.6),
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(30)),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withOpacity(0.02),
                              blurRadius: 10,
                              offset: const Offset(0, -5))
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(scheduleTitle,
                              style: mainFont.copyWith(
                                  fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 16),
                          events.isEmpty
                              ? Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 40),
                                  child: Center(
                                      child: Text(
                                          loc['calendar_empty'] ??
                                              'No schedule',
                                          style: mainFont)),
                                )
                              : ListView.separated(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  padding: EdgeInsets.zero,
                                  itemCount: events.length,
                                  separatorBuilder: (context, index) =>
                                      const SizedBox(height: 12),
                                  itemBuilder: (context, index) {
                                    // <<< استفاده از ویجت ScheduleCard >>>
                                    return ScheduleCard(
                                      event: events[index],
                                      font: mainFont,
                                      isPersian: isPersian,
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
          ],
        ),
      ),
      bottomNavigationBar: CareMateBottomNav(
        currentIndex: 0,
        onTap: (index) {
          if (index == 4) {
            Navigator.pushReplacement(
              context,
              PageRouteBuilder(
                pageBuilder: (context, animation1, animation2) =>
                    const DashboardScreen(),
                transitionDuration: Duration.zero,
                reverseTransitionDuration: Duration.zero,
              ),
            );
          }
        },
      ),
    );
  }
}
