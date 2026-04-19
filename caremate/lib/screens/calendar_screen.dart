import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart'; // پکیج google_fonts حذف شد

import '../localization/app_localizations.dart';
import '../localization/locale_provider.dart';
import 'profile_screen.dart'; 
import 'dashboard_screen.dart'; 
import 'caremate_bottom_nav.dart'; 

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

  final Color bgColor = const Color(0xFFDFE9F5);
  final Color primaryText = const Color(0xFF2B3A60);

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

    // فونت‌های اختصاصی CareMate (اصلاح شده برای استفاده از فونت محلی)
    final TextStyle mainFont = isPersian
        ? TextStyle(fontFamily: 'Vazir', color: primaryText)
        : TextStyle(fontFamily: 'Poppins', color: primaryText);
    
    final TextStyle titleFont = isPersian
        ? TextStyle(fontFamily: 'Vazir', fontSize: 22, fontWeight: FontWeight.bold, color: const Color(0xFF33416E))
        : TextStyle(fontFamily: 'Poppins', fontSize: 22, fontWeight: FontWeight.bold, color: const Color(0xFF33416E));

    final events = _getEventsForDay(_selectedDate);
    final dayFormat = DateFormat('d').format(_selectedDate);
    final scheduleTitle = "${loc['calendar_schedule_for'] ?? 'Schedule for'} ${dayFormat}th";

    return Scaffold(
      backgroundColor: bgColor,
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
                      Container(
                        width: 48, height: 48,
                        decoration: BoxDecoration(color: const Color(0xFFF0F4FA), shape: BoxShape.circle, boxShadow: [
                          const BoxShadow(color: Colors.white, offset: Offset(-4, -4), blurRadius: 8),
                          BoxShadow(color: Colors.black.withOpacity(0.05), offset: const Offset(4, 4), blurRadius: 8),
                        ]),
                        child: const Icon(Icons.arrow_back_ios_new, color: Colors.black54, size: 20),
                      ),
                      Text(loc['calendar_title'] ?? 'Calendar', style: titleFont),
                      GestureDetector(
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen())),
                        child: Container(
                          width: 48, height: 48,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFFF0F4FA), boxShadow: [
                            const BoxShadow(color: Colors.white, offset: Offset(-4, -4), blurRadius: 8),
                            BoxShadow(color: Colors.black.withOpacity(0.1), offset: const Offset(4, 4), blurRadius: 8),
                          ]),
                          padding: const EdgeInsets.all(4),
                          child: const CircleAvatar(backgroundColor: Color(0xFFE2D4C8), child: Icon(Icons.person, color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                ),

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
                  child: _buildCalendarCard(context, mainFont),
                ),

                const SizedBox(height: 25),

                Expanded(
                  child: Container(
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
                        Expanded(
                          child: events.isEmpty
                              ? Center(child: Text(loc['calendar_empty'] ?? 'No schedule', style: mainFont))
                              : ListView.separated(
                                  padding: const EdgeInsets.only(bottom: 100), 
                                  itemCount: events.length,
                                  separatorBuilder: (context, index) => const SizedBox(height: 12),
                                  itemBuilder: (context, index) {
                                    return _buildScheduleCard(events[index], mainFont);
                                  },
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
                  if (index == 3) { 
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
          color: isSelected ? const Color(0xFF2C3E50) : Colors.white.withOpacity(0.5),
          borderRadius: BorderRadius.circular(20),
          boxShadow: isSelected ? [BoxShadow(color: const Color(0xFF2C3E50).withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))] : [],
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: isSelected ? Colors.white : primaryText),
            const SizedBox(width: 8),
            Text(label, style: font.copyWith(color: isSelected ? Colors.white : primaryText, fontWeight: FontWeight.bold, fontSize: 14)),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendarCard(BuildContext context, TextStyle font) {
    final daysInMonth = DateUtils.getDaysInMonth(_focusedMonth.year, _focusedMonth.month);
    final firstDayOfMonth = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final weekDayOffset = firstDayOfMonth.weekday % 7; 

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.85),
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(color: Colors.white.withOpacity(0.8), offset: const Offset(-6, -6), blurRadius: 12),
          BoxShadow(color: const Color(0xFFA6BCCF).withOpacity(0.3), offset: const Offset(6, 6), blurRadius: 12),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(Icons.calendar_month, color: primaryText, size: 20),
              Row(
                children: [
                  IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _changeMonth(-1), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
                  const SizedBox(width: 10),
                  Text(DateFormat('MMMM yyyy').format(_focusedMonth), style: font.copyWith(fontSize: 16, fontWeight: FontWeight.bold)),
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
                    color: isSelected ? const Color(0xFF2C3E50) : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$dayNum',
                        style: font.copyWith(
                          color: isSelected ? Colors.white : primaryText,
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

  Widget _buildScheduleCard(Map<String, dynamic> item, TextStyle font) {
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
                Text(item['subtitle'], style: font.copyWith(fontSize: 13, color: Colors.grey[600])),
              ],
            ),
          ),
          const Icon(Icons.more_vert, color: Colors.grey),
        ],
      ),
    );
  }
}
