import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/localization/locale_provider.dart';
import '../../core/utils/string_extensions.dart';
import '../../core/constants/app_colors.dart';
import '../widgets/caremate_bottom_nav.dart';
import 'profile_screen.dart';
import 'dashboard_screen.dart';

// ایمپورت مدل‌ها و داده‌های ساختگی
import '../../models/user_model.dart';
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

  // <<< فانکشن‌های کمکی جدید >>>
  // ۱. ترکیب تاریخ و زمان برای مقایسه‌های دقیق
  DateTime _getEventDateTime(EventModel event) {
    final timeParts = event.time.split(':');
    return DateTime(event.date.year, event.date.month, event.date.day,
        int.parse(timeParts[0]), int.parse(timeParts[1]));
  }

  // ۲. پیدا کردن تمام رویدادهایی که زمانشان گذشته و انجام نشده‌اند
  List<EventModel> _getOverdueEvents() {
    final now = DateTime.now();
    return AppMockData.calendarEvents.where((event) {
      final eventDateTime = _getEventDateTime(event);
      // اگر زمان گذشته باشد و وضعیت انجام آن false یا null باشد
      return eventDateTime.isBefore(now) && (event.isCompleted == false || event.isCompleted == null);
    }).toList();
  }

  // ۳. نمایش پاپ‌آپ (Bottom Sheet) برای رویدادهای فراموش شده
  void _showOverduePopup(BuildContext context, List<EventModel> overdueEvents) {
    if (overdueEvents.isEmpty) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('یادآوری‌های تاخیر دار',
                  style: TextStyle(fontFamily: 'Vazir', fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red)),
              const SizedBox(height: 10),
              Flexible( // برای جلوگیری از overflow در لیست‌های بلند
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: overdueEvents.length,
                  itemBuilder: (context, index) {
                    final event = overdueEvents[index];
                    final user = AppMockData.familyMembers.firstWhere((u) => u.id == event.userId);
                    return ListTile(
                      title: Text('${event.title} (${user.name})', style: const TextStyle(fontFamily: 'Vazir')),
                      subtitle: Text('زمان: ${event.time}', style: const TextStyle(fontFamily: 'Vazir')),
                      trailing: IconButton(
                        icon: Icon(Icons.phone, color: AppColors.primaryBlue),
                        onPressed: () {
                          // در اینجا کدهای برقراری تماس قرار می‌گیرد (مثلا با url_launcher)
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('در حال تماس با ${user.name}...', style: const TextStyle(fontFamily: 'Vazir'))));
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
  // <<< پایان فانکشن‌های کمکی جدید >>>

  DateTime _normalizeDate(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  List<EventModel> _getEventsForDayAndUser(DateTime day, String userId) {
    return AppMockData.calendarEvents.where((event) {
      return _normalizeDate(event.date) == _normalizeDate(day) && event.userId == userId;
    }).toList();
  }

  bool _hasEventForUser(DateTime day, String userId) {
    return AppMockData.calendarEvents
        .any((event) => _normalizeDate(event.date) == _normalizeDate(day) && event.userId == userId);
  }

  void _onDaySelected(DateTime day) {
    setState(() {
      _selectedDate = day;
    });
  }

  void _changeMonth(int offset) {
    setState(() {
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + offset);
    });
  }

  IconData _getIconForRole(String role) {
    switch (role) {
      case 'مادر': return Icons.pregnant_woman;
      case 'فرزند': return Icons.child_care;
      case 'پدر': // آیکون برای پدر
      case 'همسر': return Icons.favorite;
      default: return Icons.person;
    }
  }

  Map<String, dynamic> _getEventTheme(EventType type) {
    switch (type) {
      case EventType.medicine:
        return {'color': Colors.pinkAccent, 'icon': Icons.medication};
      case EventType.doctor:
        return {'color': Colors.blueAccent, 'icon': Icons.medical_services};
      case EventType.checkup:
        return {'color': Colors.orangeAccent, 'icon': Icons.vaccines};
      case EventType.other:
      default:
        return {'color': AppColors.darkBlue, 'icon': Icons.event};
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final localeProvider = Provider.of<LocaleProvider>(context);
    final isPersian = localeProvider.locale.languageCode == 'fa';
    final TextStyle mainFont = isPersian
        ? const TextStyle(fontFamily: 'Vazir', color: AppColors.primaryText)
        : const TextStyle(fontFamily: 'Nunito', color: AppColors.primaryText);
    final TextStyle titleFont = isPersian
        ? const TextStyle(fontFamily: 'Vazir', fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.darkBlue)
        : const TextStyle(fontFamily: 'Nunito', fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.darkBlue);

    final events = _getEventsForDayAndUser(_selectedDate, _selectedUserId);
    final dayFormat = DateFormat('d').format(_selectedDate);
    final scheduleTitle =
        "${loc['calendar_schedule_for'] ?? 'Schedule for'} $dayFormat${isPersian ? '' : 'th'}".toPersianDigit(isPersian);

    // <<< دریافت لیست رویدادهای فراموش شده برای نمایش دات قرمز >>>
    final overdueEvents = _getOverdueEvents();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // <<< ویجت زنگوله نوتیفیکیشن >>>
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppColors.lightContainer,
                          shape: BoxShape.circle,
                          boxShadow: [
                            const BoxShadow(color: Colors.white, offset: Offset(-4, -4), blurRadius: 8),
                            BoxShadow(color: Colors.black.withOpacity(0.05), offset: const Offset(4, 4), blurRadius: 8),
                          ],
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.notifications_none_rounded, color: Colors.black54, size: 22),
                              onPressed: () => _showOverduePopup(context, overdueEvents),
                            ),
                            if (overdueEvents.isNotEmpty)
                              Positioned(
                                top: 12,
                                right: 12,
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                                ),
                              ),
                          ],
                        ),
                      ),
                      // <<< پایان ویجت زنگوله نوتیفیکیشن >>>
                      Text(loc['calendar_title'] ?? 'Calendar', style: titleFont),
                      GestureDetector(
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen())),
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.lightContainer, boxShadow: [
                            const BoxShadow(color: Colors.white, offset: Offset(-4, -4), blurRadius: 8),
                            BoxShadow(color: Colors.black.withOpacity(0.1), offset: const Offset(4, 4), blurRadius: 8),
                          ]),
                          padding: const EdgeInsets.all(4),
                          child: const CircleAvatar(
                              backgroundColor: AppColors.avatarBackground, child: Icon(Icons.person, color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 120),
                    child: Column(
                      children: [
                        const SizedBox(height: 15),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Row(
                            children: AppMockData.familyMembers.map((user) {
                              return Padding(
                                padding: const EdgeInsets.only(right: 12),
                                child: _buildUserChip(
                                  id: user.id,
                                  label: user.name,
                                  icon: _getIconForRole(user.role),
                                  font: mainFont,
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: _buildCalendarCard(context, mainFont, isPersian),
                        ),
                        const SizedBox(height: 25),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.6),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, -5))
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(scheduleTitle, style: mainFont.copyWith(fontSize: 18, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 16),
                              events.isEmpty
                                  ? Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 40),
                                      child: Center(child: Text(loc['calendar_empty'] ?? 'No schedule', style: mainFont)),
                                    )
                                  : ListView.separated(
                                      shrinkWrap: true,
                                      physics: const NeverScrollableScrollPhysics(),
                                      padding: EdgeInsets.zero,
                                      itemCount: events.length,
                                      separatorBuilder: (context, index) => const SizedBox(height: 12),
                                      itemBuilder: (context, index) {
                                        // <<< ارسال پارامترها به کارت هوشمند شده >>>
                                        return _buildScheduleCard(events[index], mainFont, isPersian);
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
            Positioned(
              bottom: 30,
              left: 20,
              right: 20,
              child: CareMateBottomNav(
                currentIndex: 0,
                onTap: (index) {
                  if (index == 4) {
                    Navigator.pushReplacement(
                      context,
                      PageRouteBuilder(
                        pageBuilder: (context, animation1, animation2) => const DashboardScreen(),
                        transitionDuration: Duration.zero,
                        reverseTransitionDuration: Duration.zero,
                      ),
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserChip({required String id, required String label, required IconData icon, required TextStyle font}) {
    final bool isSelected = _selectedUserId == id;
    return GestureDetector(
      onTap: () => setState(() => _selectedUserId = id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.darkBlue : Colors.white.withOpacity(0.5),
          borderRadius: BorderRadius.circular(20),
          boxShadow: isSelected ? [BoxShadow(color: AppColors.darkBlue.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))] : [],
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: isSelected ? Colors.white : AppColors.primaryText),
            const SizedBox(width: 8),
            Text(label, style: font.copyWith(color: isSelected ? Colors.white : AppColors.primaryText, fontWeight: FontWeight.bold, fontSize: 14)),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendarCard(BuildContext context, TextStyle font, bool isPersian) {
    final daysInMonth = DateUtils.getDaysInMonth(_focusedMonth.year, _focusedMonth.month);
    final firstDayOfMonth = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final weekDayOffset = firstDayOfMonth.weekday % 7;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppColors.softDecoration(color: Colors.white.withOpacity(0.85)),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Icon(Icons.calendar_month, color: AppColors.primaryText, size: 20),
              Row(
                children: [
                  IconButton(
                      icon: const Icon(Icons.chevron_left), onPressed: () => _changeMonth(-1), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
                  const SizedBox(width: 10),
                  Text(DateFormat('MMMM yyyy').format(_focusedMonth).toPersianDigit(isPersian), style: font.copyWith(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 10),
                  IconButton(
                      icon: const Icon(Icons.chevron_right), onPressed: () => _changeMonth(1), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: ['S', 'M', 'T', 'W', 'T', 'F', 'S'].map((d) => SizedBox(
              width: 30, child: Center(child: Text(d, style: font.copyWith(fontWeight: FontWeight.bold, color: Colors.grey[600]))),
            )).toList(),
          ),
          const SizedBox(height: 10),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: daysInMonth + weekDayOffset,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, mainAxisSpacing: 8, crossAxisSpacing: 8),
            itemBuilder: (context, index) {
              if (index < weekDayOffset) return const SizedBox();

              final dayNum = index - weekDayOffset + 1;
              final currentDayDate = DateTime(_focusedMonth.year, _focusedMonth.month, dayNum);
              final isSelected = _normalizeDate(_selectedDate) == currentDayDate;

              final hasEvent = _hasEventForUser(currentDayDate, _selectedUserId);

              return GestureDetector(
                onTap: () => _onDaySelected(currentDayDate),
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
                          color: isSelected ? Colors.white : AppColors.primaryText,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      if (hasEvent && !isSelected) ...[
                        const SizedBox(height: 4),
                        Container(width: 5, height: 5, decoration: const BoxDecoration(color: Colors.pinkAccent, shape: BoxShape.circle)),
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

  // <<< ویجت هوشمند شده کارت رویداد >>>
  Widget _buildScheduleCard(EventModel event, TextStyle font, bool isPersian) {
    final theme = _getEventTheme(event.type);

    // ۱. بررسی وضعیت زمانی و انجام رویداد
    final now = DateTime.now();
    final eventDateTime = _getEventDateTime(event);
    final bool isPast = eventDateTime.isBefore(now);
    final bool isOverdue = isPast && (event.isCompleted == false || event.isCompleted == null);

    // ۲. تعیین رنگ کارت بر اساس وضعیت
    final Color cardColor = isOverdue ? Colors.amber.shade100 : Colors.white;

    // ۳. تعیین آیکون وضعیت (تیک، ضربدر یا ساعت)
    final Widget statusIcon;
    if (isPast) {
      statusIcon = event.isCompleted == true
          ? const Icon(Icons.check_circle, color: Colors.green)
          : const Icon(Icons.cancel, color: Colors.red);
    } else {
      statusIcon = const Icon(Icons.access_time_filled_rounded, color: Colors.grey);
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor, // <<< استفاده از رنگ دینامیک
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), offset: const Offset(2, 4), blurRadius: 8),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (theme['color'] as Color).withOpacity(0.15),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(theme['icon'], color: theme['color'], size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event.title, style: font.copyWith(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                  event.description != null
                      ? '${event.time} - ${event.description}'.toPersianDigit(isPersian)
                      : event.time.toPersianDigit(isPersian),
                  style: font.copyWith(fontSize: 13, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          statusIcon, 
        ],
      ),
    );
  }
}
