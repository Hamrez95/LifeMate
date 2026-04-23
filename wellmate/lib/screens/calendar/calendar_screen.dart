import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:wellmate/core/theme/app_style.dart';
import '../../localization/app_localizations.dart';
import '../../core/widgets/custom_header.dart';
import '../profile/profile_screen.dart';
import '../../models/schedule_item_model.dart';
import '../../core/utils/string_extensions.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({Key? key}) : super(key: key);

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _selectedDate = DateTime.now();
  DateTime _focusedMonth = DateTime.now();

  late Map<DateTime, List<ScheduleItemModel>> _events;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    final day18 = DateTime(today.year, today.month, 18);
    final day19 = DateTime(today.year, today.month, 19);
    final day20 = DateTime(today.year, today.month, 20);

    // داده‌های تستی با استفاده از ScheduleItemModel
    _events = {
      day18: [
        ScheduleItemModel(
          id: '1',
          type: 'medicine',
          title: 'Cetirizine (10mg)',
          time: '18:30',
          dosage: '1',
        ),
        ScheduleItemModel(
          id: '2',
          type: 'doctor',
          title: 'Dr. Siamaki (Orthopedist)',
          time: '18:30',
          dosage: '',
        ),
        ScheduleItemModel(
          id: '3',
          type: 'medicine',
          title: 'Propranolol (Heart)',
          time: '21:30',
          dosage: '1',
        ),
        ScheduleItemModel(
          id: '4',
          type: 'treatment',
          title: 'Ketorolac Injection',
          time: '22:00',
          dosage: '',
        ),
      ],
      day19: [
        ScheduleItemModel(
          id: '5',
          type: 'medicine',
          title: 'Amoxicillin',
          time: '08:00',
          dosage: '2',
        )
      ],
      day20: [
        ScheduleItemModel(
          id: '6',
          type: 'doctor',
          title: 'Dr. Rad (Dentist)',
          time: '10:00',
          dosage: '',
        )
      ]
    };
  }

  DateTime _normalizeDate(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  List<ScheduleItemModel> _getEventsForDay(DateTime day) {
    return _events[_normalizeDate(day)] ?? [];
  }

  void _onDaySelected(DateTime day) {
    setState(() {
      _selectedDate = day;
    });
  }

  void _changeMonth(int offset) {
    setState(() {
      _focusedMonth =
          DateTime(_focusedMonth.year, _focusedMonth.month + offset, 1);
    });
  }

  // --- متدهای کمکی برای تشخیص گرافیک بر اساس نوع ---
  IconData _getIconForType(String type) {
    switch (type) {
      case 'doctor':
        return Icons.person;
      case 'treatment':
        return Icons.medical_services;
      case 'medicine':
      default:
        return Icons.medication;
    }
  }

  Color _getColorForType(String type) {
    switch (type) {
      case 'doctor':
        return Colors.blueAccent;
      case 'treatment':
        return Colors.orangeAccent;
      case 'medicine':
        return Colors.pinkAccent;
      default:
        return Colors.green;
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final events = _getEventsForDay(_selectedDate);
    final isPersian = Localizations.localeOf(context).languageCode == 'fa';
    final dayFormat =
        DateFormat('d').format(_selectedDate).toPersianDigit(isPersian);

    final scheduleTitle = isPersian
        ? "${loc['calendar_schedule_for'] ?? 'برنامه روز'} $dayFormat"
        : "${loc['calendar_schedule_for'] ?? 'Schedule for'} ${dayFormat}th";

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(80),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 10),
          child: CustomHeader(
            title: loc['calendar_title'] ?? 'Schedule',
            onProfileTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
            },
            font: AppTextStyles.heading(context),
          ),
        ),
      ),
      // قسمت bottomNavigationBar حذف شد تا تداخلی ایجاد نکند
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 20),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Text(
                loc['calendar_select_date'] ?? 'Select a date to view schedule',
                style: AppTextStyles.body(context),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: _buildCalendarCard(context, isPersian),
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
                      offset: const Offset(0, -5),
                    )
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      scheduleTitle,
                      style:
                          AppTextStyles.heading(context).copyWith(fontSize: 18),
                    ),
                    const SizedBox(height: 16),
                    events.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 40),
                            child: Center(
                              child: Text(
                                loc['calendar_empty'] ?? 'No schedule',
                                style: AppTextStyles.body(context),
                              ),
                            ),
                          )
                        : GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            padding: EdgeInsets.zero,
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                              childAspectRatio: 1.55,
                            ),
                            itemCount: events.length,
                            itemBuilder: (context, index) {
                              return _buildScheduleCard(
                                  context, events[index], loc, isPersian);
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

  Widget _buildScheduleCard(BuildContext context, ScheduleItemModel item,
      dynamic loc, bool isPersian) {
    final itemColor = _getColorForType(item.type);
    final itemIcon = _getIconForType(item.type);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: AppColors.shadowDark,
              offset: const Offset(2, 2),
              blurRadius: 5),
          BoxShadow(
              color: AppColors.shadowLight,
              offset: const Offset(-2, -2),
              blurRadius: 5),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: itemColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(itemIcon, color: itemColor, size: 20),
          ),
          const SizedBox(height: 10),
          Text(item.title.toPersianDigit(isPersian),
              style: AppTextStyles.get(context,
                  fontSize: 13, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(item.time.toPersianDigit(isPersian),
              style: AppTextStyles.caption(context).copyWith(fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          if (item.dosage.isNotEmpty) ...[
            const SizedBox(height: 4),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Text(
                  "${loc['med_qty'] ?? 'Qty'}: ${item.dosage.toPersianDigit(isPersian)}",
                  style: AppTextStyles.caption(context).copyWith(fontSize: 11)),
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildCalendarCard(BuildContext context, bool isPersian) {
    final daysInMonth =
        DateUtils.getDaysInMonth(_focusedMonth.year, _focusedMonth.month);
    final firstDayOfMonth =
        DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final weekDayOffset = firstDayOfMonth.weekday % 7;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
              color: AppColors.shadowDark,
              offset: const Offset(5, 5),
              blurRadius: 15),
          BoxShadow(
              color: AppColors.shadowLight,
              offset: const Offset(-5, -5),
              blurRadius: 15),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(Icons.calendar_month_outlined,
                  color: AppColors.textPrimary, size: 20),
              Row(
                children: [
                  IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: () => _changeMonth(-1),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints()),
                  const SizedBox(width: 10),
                  Text(
                      DateFormat('MMMM yyyy')
                          .format(_focusedMonth)
                          .toPersianDigit(isPersian),
                      style: AppTextStyles.heading(context)
                          .copyWith(fontSize: 16)),
                  const SizedBox(width: 10),
                  IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: () => _changeMonth(1),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints()),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: ['S', 'M', 'T', 'W', 'T', 'F', 'S']
                .map((d) => SizedBox(
                      width: 30,
                      child: Center(
                          child: Text(d,
                              style: AppTextStyles.body(context)
                                  .copyWith(fontWeight: FontWeight.bold))),
                    ))
                .toList(),
          ),
          const SizedBox(height: 10),
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
                  DateTime(_focusedMonth.year, _focusedMonth.month, dayNum);
              final isSelected =
                  _normalizeDate(_selectedDate) == currentDayDate;
              final hasEvent = _events.containsKey(currentDayDate);

              return GestureDetector(
                onTap: () => _onDaySelected(currentDayDate),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  decoration: BoxDecoration(
                    color:
                        isSelected ? AppColors.primary : AppColors.background,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: isSelected
                        ? []
                        : [
                            BoxShadow(
                              color: AppColors.shadowDark,
                              offset: const Offset(2, 2),
                              blurRadius: 4,
                            ),
                            BoxShadow(
                              color: AppColors.shadowLight,
                              offset: const Offset(-2, -2),
                              blurRadius: 4,
                            ),
                          ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$dayNum'.toPersianDigit(isPersian),
                        style: AppTextStyles.get(
                          context,
                          color:
                              isSelected ? Colors.white : AppColors.textPrimary,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 14,
                        ),
                      ),
                      if (hasEvent && !isSelected) ...[
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                                width: 4,
                                height: 4,
                                decoration: const BoxDecoration(
                                    color: Colors.green,
                                    shape: BoxShape.circle)),
                            const SizedBox(width: 2),
                            Container(
                                width: 4,
                                height: 4,
                                decoration: const BoxDecoration(
                                    color: Colors.pink,
                                    shape: BoxShape.circle)),
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
}
