import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:wellmate/core/theme/app_style.dart';
import '../../localization/app_localizations.dart';
import '../../core/widgets/wellmate_app_header.dart';
import '../profile/profile_screen.dart';
import '../../models/schedule_item_model.dart';
import '../../core/utils/string_extensions.dart';

// ایمپورت ویجت‌های جدا شده
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

  late Map<DateTime, List<ScheduleItemModel>> _events;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();

    // دیتای تستی
    _events = {
      DateTime(today.year, today.month, 18): [
        ScheduleItemModel(
            id: '1',
            type: 'medicine',
            title: 'Cetirizine (10mg)',
            time: '18:30',
            dosage: '1'),
        ScheduleItemModel(
            id: '2',
            type: 'doctor',
            title: 'Dr. Siamaki (Orthopedist)',
            time: '18:30',
            dosage: ''),
      ],
      DateTime(today.year, today.month, 19): [
        ScheduleItemModel(
            id: '5',
            type: 'medicine',
            title: 'Amoxicillin',
            time: '08:00',
            dosage: '2')
      ],
      DateTime(today.year, today.month, 20): [
        ScheduleItemModel(
            id: '6',
            type: 'doctor',
            title: 'Dr. Rad (Dentist)',
            time: '10:00',
            dosage: '')
      ]
    };
  }

  DateTime _normalizeDate(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  List<ScheduleItemModel> _getEventsForDay(DateTime day) =>
      _events[_normalizeDate(day)] ?? [];

  Set<String> _getDayEventTypes(DateTime day) {
    return _getEventsForDay(day).map((event) => event.type).toSet();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final isPersian = Localizations.localeOf(context).languageCode == 'fa';
    final events = _getEventsForDay(_selectedDate);

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
          padding: const EdgeInsets.only(
              bottom: 20, top: 10), // کمی فاصله از بالا دادیم
          child: Column(
            children: [
              // هدر از اینجا حذف شد تا دو بار نمایش داده نشود
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: CustomTableCalendar(
                  focusedMonth: _focusedMonth,
                  selectedDate: _selectedDate,
                  isPersian: isPersian,
                  getDayEventTypes: _getDayEventTypes,
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
                    events.isEmpty
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
                            itemCount: events.length,
                            itemBuilder: (context, index) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12.0),
                                child: ScheduleItemCard(
                                  item: events[index],
                                  loc: loc,
                                  isPersian: isPersian,
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
