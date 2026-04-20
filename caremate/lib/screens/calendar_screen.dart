import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart'; 

import '../../core/localization/app_localizations.dart';
import '../../core/localization/locale_provider.dart';
import '../../core/utils/string_extensions.dart'; 
import '../../core/constants/app_colors.dart'; // 👈 اضافه شد
import '../widgets/caremate_bottom_nav.dart'; // 👈 مسیر را بر اساس پوشه ویجت‌ها تنظیم کنید
import 'profile_screen.dart'; 
import 'dashboard_screen.dart'; 

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({Key? key}) : super(key: key);

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _selectedDate = DateTime.now();
  DateTime _focusedMonth = DateTime.now();
  late Map<DateTime, List<Map<String, dynamic>>> _events;
  
  String _selectedUser = 'Mother';

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    final day18 = DateTime(today.year, today.month, 18);
    final day19 = DateTime(today.year, today.month, 19);

    _events = {
      day18: [
        {'title': 'Prenatal Vitamins', 'subtitle': '08:00 AM', 'icon': Icons.medication, 'color': Colors.pinkAccent},
        {'title': 'Dr. Siamaki', 'subtitle': 'Checkup\n10:30 AM', 'icon': Icons.medical_services, 'color': Colors.blueAccent},
      ],
      day19: [
        {'title': 'Baby Vaccination', 'subtitle': '09:00 AM', 'icon': Icons.vaccines, 'color': Colors.orangeAccent}
      ],
    };
  }

  DateTime _normalizeDate(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  List<Map<String, dynamic>> _getEventsForDay(DateTime day) {
    return _events[_normalizeDate(day)] ?? [];
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

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final localeProvider = Provider.of<LocaleProvider>(context);
    final isPersian = localeProvider.locale.languageCode == 'fa';

    final TextStyle mainFont = isPersian
        ? const TextStyle(fontFamily: 'Vazir', color: AppColors.primaryText)
        : const TextStyle(fontFamily: 'Nunito', color: AppColors.primaryText); // 👈 یکپارچه‌سازی با فونت Main
    
    final TextStyle titleFont = isPersian
        ? const TextStyle(fontFamily: 'Vazir', fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.darkBlue)
        : const TextStyle(fontFamily: 'Nunito', fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.darkBlue);

    final events = _getEventsForDay(_selectedDate);
    final dayFormat = DateFormat('d').format(_selectedDate);
    
    final scheduleTitle = "${loc['calendar_schedule_for'] ?? 'Schedule for'} $dayFormat${isPersian ? '' : 'th'}".toPersianDigit(isPersian);

    return Scaffold(
      backgroundColor: AppColors.background, // 👈 استفاده از پالت رنگ
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                // ۱. هدر
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        width: 48, height: 48,
                        decoration: BoxDecoration(color: AppColors.lightContainer, shape: BoxShape.circle, boxShadow: [
                          const BoxShadow(color: Colors.white, offset: Offset(-4, -4), blurRadius: 8),
                          BoxShadow(color: Colors.black.withOpacity(0.05), offset: const Offset(4, 4), blurRadius: 8),
                        ]),
                        child: const Icon(Icons.notifications_none_rounded, color: Colors.black54, size: 20),
                      ),
                      Text(loc['calendar_title'] ?? 'Calendar', style: titleFont),
                      GestureDetector(
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen())),
                        child: Container(
                          width: 48, height: 48,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.lightContainer, boxShadow: [
                            const BoxShadow(color: Colors.white, offset: Offset(-4, -4), blurRadius: 8),
                            BoxShadow(color: Colors.black.withOpacity(0.1), offset: const Offset(4, 4), blurRadius: 8),
                          ]),
                          padding: const EdgeInsets.all(4),
                          child: const CircleAvatar(backgroundColor: AppColors.avatarBackground, child: Icon(Icons.person, color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                ),

                // ۲. محتوای قابل اسکرول
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
                            children: [
                              _buildUserChip('Mother', loc['user_mother'] ?? 'Mother', Icons.pregnant_woman, mainFont),
                              const SizedBox(width: 12),
                              _buildUserChip('Baby', loc['user_baby'] ?? 'Baby', Icons.child_care, mainFont),
                              const SizedBox(width: 12),
                              _buildUserChip('Partner', loc['user_partner'] ?? 'Partner', Icons.favorite, mainFont),
                            ],
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
                               BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, -5))
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

            // نویگیشن بار 
            Positioned(
              bottom: 30,
              left: 20,
              right: 20,
              child: CareMateBottomNav(
                currentIndex: 0, // ایندکس تقویم
                onTap: (index) {
                  if (index == 4) { // 👈 اصلاح شد: ایندکس 4 برای رفتن به داشبورد
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

  Widget _buildUserChip(String id, String label, IconData icon, TextStyle font) {
    final bool isSelected = _selectedUser == id;
    return GestureDetector(
      onTap: () => setState(() => _selectedUser = id),
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
      decoration: AppColors.softDecoration(color: Colors.white.withOpacity(0.85)), // 👈 استفاده از استایل نئومورفیسم متمرکز
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Icon(Icons.calendar_month, color: AppColors.primaryText, size: 20),
              Row(
                children: [
                  IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _changeMonth(-1), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
                  const SizedBox(width: 10),
                  Text(DateFormat('MMMM yyyy').format(_focusedMonth).toPersianDigit(isPersian), style: font.copyWith(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 10),
                  IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => _changeMonth(1), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
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
              final hasEvent = _events.containsKey(currentDayDate);

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

  Widget _buildScheduleCard(Map<String, dynamic> item, TextStyle font, bool isPersian) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
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
              color: (item['color'] as Color).withOpacity(0.15),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(item['icon'], color: item['color'], size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item['title'], style: font.copyWith(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(item['subtitle'].toString().toPersianDigit(isPersian), style: font.copyWith(fontSize: 13, color: Colors.grey[600])),
              ],
            ),
          ),
          const Icon(Icons.more_vert, color: Colors.grey),
        ],
      ),
    );
  }
}
