import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // برای فرمت تاریخ (در pubspec.yaml داشته باشید)

// --- ایمپورت‌های پروژه شما ---
import '../localization/app_localizations.dart';
import 'app_style.dart';
import 'shared_widgets.dart';
import 'profile_screen.dart'; // برای نویگیشن هدر

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({Key? key}) : super(key: key);

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  // تاریخ انتخاب شده و ماه فعلی تقویم
  DateTime _selectedDate = DateTime.now();
  DateTime _focusedMonth = DateTime.now();

  // --- دیتای ساختگی (Mock Data) ---
  // کلید: تاریخ (بدون زمان)، مقدار: لیست رویدادها
  late Map<DateTime, List<Map<String, dynamic>>> _events;

  @override
  void initState() {
    super.initState();
    // تنظیم دیتای تستی برای امروز و چند روز آینده
    final today = DateTime.now();
    final day18 = DateTime(today.year, today.month, 18);
    final day19 = DateTime(today.year, today.month, 19);
    final day20 = DateTime(today.year, today.month, 20);

    _events = {
      // دیتا برای روز ۱۸م (طبق تصویر)
      day18: [
        {
          'type': 'medicine',
          'title': 'Cetirizine (10mg)',
          'subtitle': '18:30',
          'qty': '1',
          'icon': Icons.medication,
          'color': Colors.pinkAccent,
        },
        {
          'type': 'doctor',
          'title': 'Dr. Siamaki',
          'subtitle': 'Orthopedist\n18:30',
          'qty': null,
          'icon': Icons.person,
          'color': Colors.blueAccent,
        },
        {
          'type': 'medicine',
          'title': 'Propranolol (Heart)',
          'subtitle': '21:30',
          'qty': '1',
          'icon': Icons.favorite,
          'color': Colors.redAccent,
        },
        {
          'type': 'treatment',
          'title': 'Ketorolac Injection',
          'subtitle': '22:00',
          'qty': null,
          'icon': Icons.medical_services,
          'color': Colors.orangeAccent,
        },
      ],
      // دیتا برای روز ۱۹م
      day19: [
        {
          'type': 'medicine',
          'title': 'Amoxicillin',
          'subtitle': '08:00',
          'qty': '2',
          'icon': Icons.circle,
          'color': Colors.green,
        }
      ],
      // دیتا برای روز ۲۰م
      day20: [
         {
          'type': 'doctor',
          'title': 'Dr. Rad',
          'subtitle': 'Dentist\n10:00',
          'qty': null,
          'icon': Icons.person_outline,
          'color': Colors.purple,
        }
      ]
    };
    
    // اگر امروز ۱۸م نیست، برای تست تاریخ را روی ۱۸م ست می‌کنیم یا همان امروز
    // _selectedDate = day18; // (اختیاری: برای اینکه دقیقا مثل عکس شروع شود)
  }

  // نرمال‌سازی تاریخ (حذف ساعت و دقیقه برای مقایسه)
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
    final events = _getEventsForDay(_selectedDate);

    // فرمت تاریخ برای نمایش (مثلاً: 18th)
    final dayFormat = DateFormat('d').format(_selectedDate);
    final scheduleTitle = "${loc['calendar_schedule_for']} ${dayFormat}th";

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                // 1. Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 10),
                  child: CustomHeader(
                    title: loc['calendar_title'] ?? 'Schedule',
                    onProfileTap: () {
                       Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const ProfileScreen()));
                    },
                  ),
                ),

                const SizedBox(height: 10),
                Text(
                  loc['calendar_select_date'] ?? 'Select a date to view schedule',
                  style: AppTextStyles.body(context),
                ),
                const SizedBox(height: 20),

                // 2. Calendar Widget (Custom Neumorphic Calendar)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: _buildCalendarCard(context),
                ),

                const SizedBox(height: 25),

                // 3. Schedule List (Gray Container Area)
                Expanded(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8ECEF), // رنگ طوسی روشن برای کانتینر پایین
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                      boxShadow: [
                         BoxShadow(
                           color: Colors.black.withOpacity(0.05),
                           blurRadius: 10,
                           offset: const Offset(0, -5),
                         )
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          scheduleTitle,
                          style: AppTextStyles.header(context).copyWith(fontSize: 18),
                        ),
                        const SizedBox(height: 16),
                        
                        // Grid of Cards
                        Expanded(
                          child: events.isEmpty
                              ? Center(
                                  child: Text(
                                    loc['calendar_empty'] ?? 'No schedule',
                                    style: AppTextStyles.body(context),
                                  ),
                                )
                              : GridView.builder(
                                  padding: const EdgeInsets.only(bottom: 100), // فضا برای نویگیشن بار
                                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    crossAxisSpacing: 16,
                                    mainAxisSpacing: 16,
                                    childAspectRatio: 1.1, // نسبت ابعاد کارت‌ها
                                  ),
                                  itemCount: events.length,
                                  itemBuilder: (context, index) {
                                    return _buildScheduleCard(context, events[index], loc);
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // 4. Bottom Navigation (Active Index 3: Calendar)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: GlobalBottomNav(
                currentIndex: 3, // فرض بر اینکه آیکون تقویم ایندکس ۳ است
                addBtnLabel: loc['cal'] ?? 'cal',
                onTap: (index) {
                  // هندل کردن نویگیشن (مثلا Pop یا PushReplacement)
                  if (index == 0) Navigator.pop(context); 
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Calendar Logic & UI ---
  Widget _buildCalendarCard(BuildContext context) {
    // محاسبه روزهای ماه
    final daysInMonth = DateUtils.getDaysInMonth(_focusedMonth.year, _focusedMonth.month);
    final firstDayOfMonth = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final weekDayOffset = firstDayOfMonth.weekday % 7; // 0 for Sunday, etc.

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.bgLight,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowDark,
            offset: const Offset(5, 5),
            blurRadius: 15,
          ),
          BoxShadow(
            color: AppColors.shadowLight,
            offset: const Offset(-5, -5),
            blurRadius: 15,
          ),
        ],
      ),
      child: Column(
        children: [
          // Header: Filter Icon + Navigation
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(Icons.filter_alt_outlined, color: AppColors.primaryText, size: 20),
              
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => _changeMonth(-1),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    DateFormat('MMMM yyyy').format(_focusedMonth),
                    style: AppTextStyles.title(context).copyWith(fontSize: 16),
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () => _changeMonth(1),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          
          // Calendar Grid
          // Days of Week
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: ['S', 'M', 'T', 'W', 'T', 'F', 'S'].map((d) => SizedBox(
              width: 30,
              child: Center(child: Text(d, style: AppTextStyles.body(context).copyWith(fontWeight: FontWeight.bold))),
            )).toList(),
          ),
          const SizedBox(height: 10),
          
          // Days
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: daysInMonth + weekDayOffset,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemBuilder: (context, index) {
              if (index < weekDayOffset) return const SizedBox(); // جای خالی اول ماه
              
              final dayNum = index - weekDayOffset + 1;
              final currentDayDate = DateTime(_focusedMonth.year, _focusedMonth.month, dayNum);
              final isSelected = _normalizeDate(_selectedDate) == currentDayDate;
              final hasEvent = _events.containsKey(currentDayDate);

              return GestureDetector(
                onTap: () => _onDaySelected(currentDayDate),
                child: Container(
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF2C3E50) : Colors.transparent, // رنگ سورمه‌ای برای انتخاب
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$dayNum',
                        style: TextStyle(
                          color: isSelected ? Colors.white : AppColors.primaryText,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          fontFamily: 'Vazirmatn', // یا فونت پیش فرض شما
                        ),
                      ),
                      if (hasEvent && !isSelected) ...[
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(width: 4, height: 4, decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
                            const SizedBox(width: 2),
                            Container(width: 4, height: 4, decoration: const BoxDecoration(color: Colors.pink, shape: BoxShape.circle)),
                          ],
                        )
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

  // --- Schedule Card Widget ---
  Widget _buildScheduleCard(BuildContext context, Map<String, dynamic> item, dynamic loc) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bgLight,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            offset: const Offset(2, 2),
            blurRadius: 5,
          ),
          const BoxShadow(
            color: Colors.white,
            offset: Offset(-2, -2),
            blurRadius: 5,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon Box
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: (item['color'] as Color).withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(item['icon'], color: item['color'], size: 24),
          ),
          const Spacer(),
          // Title
          Text(
            item['title'],
            style: AppTextStyles.get(context, fontSize: 14, fontWeight: FontWeight.bold),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          // Subtitle / Time
          Text(
            item['subtitle'],
            style: AppTextStyles.body(context).copyWith(fontSize: 12),
          ),
          // Qty (Optional)
          if (item['qty'] != null) ...[
            const SizedBox(height: 4),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Text(
                "${loc['med_qty'] ?? 'Qty'}: ${item['qty']}",
                style: AppTextStyles.body(context).copyWith(fontSize: 11),
              ),
            ),
          ]
        ],
      ),
    );
  }
}
