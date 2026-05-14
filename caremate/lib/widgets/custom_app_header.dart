import 'package:flutter/material.dart';
import 'package:shamsi_date/shamsi_date.dart';
import '../screens/profile_screen.dart';
import 'custom_ui_components.dart';
import '../../models/event_model.dart';
import '../../data/app_mock_data.dart';
import '../../core/constants/app_colors.dart';
// 👈 اکستنشن اعداد را حتماً با مسیر درست ایمپورت کنید
import '../../core/utils/string_extensions.dart';

class CustomAppHeader extends StatelessWidget {
  final VoidCallback? onNotificationTap;

  const CustomAppHeader({
    Key? key,
    this.onNotificationTap,
  }) : super(key: key);

  // ۱. ترکیب تاریخ و زمان
  DateTime _getEventDateTime(EventModel event) {
    final timeParts = event.time.split(':');
    return DateTime(event.date.year, event.date.month, event.date.day,
        int.parse(timeParts[0]), int.parse(timeParts[1]));
  }

  // ۲. پیدا کردن رویدادهای تاخیر دار
  List<EventModel> _getOverdueEvents() {
    final now = DateTime.now();
    return AppMockData.calendarEvents.where((event) {
      final eventDateTime = _getEventDateTime(event);
      return eventDateTime.isBefore(now) &&
          (event.isCompleted == false || event.isCompleted == null);
    }).toList();
  }

  // ۳. نمایش پاپ‌آپ نوتیفیکیشن با استایل کاملا مشابه اپلیکیشن ۱
  void _showOverduePopup(
      BuildContext context, List<EventModel> initialOverdueEvents) {
    if (initialOverdueEvents.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('رویداد تاخیر داری وجود ندارد',
              style: TextStyle(fontFamily: 'Vazir', color: Colors.white)),
          backgroundColor: AppColors.primaryBlue,
        ),
      );
      return;
    }

    List<EventModel> currentOverdueEvents = List.from(initialOverdueEvents);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (bottomSheetContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            if (currentOverdueEvents.isEmpty) {
              Future.microtask(() => Navigator.of(context).pop());
              return const SizedBox.shrink();
            }

            return Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.warning_amber_rounded,
                            color: Colors.red.shade700),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'یادآوری‌های تاخیر دار',
                        style: TextStyle(
                            fontFamily: 'Vazir',
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.red.shade900),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.5,
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: currentOverdueEvents.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final event = currentOverdueEvents[index];
                        return _buildOverdueEventCard(
                          event,
                          context,
                          onCallTap: () {
                            setState(() {
                              currentOverdueEvents.removeAt(index);
                            });
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ۴. ساختن کارت رویداد
  Widget _buildOverdueEventCard(EventModel event, BuildContext context,
      {required VoidCallback onCallTap}) {
    final user =
        AppMockData.familyMembers.firstWhere((u) => u.id == event.userId);

    // 👈 دریافت زبان سیستم برای اعمال اکستنشن
    final isPersian = Localizations.localeOf(context).languageCode == 'fa';

    // تبدیل تاریخ میلادی به شمسی
    final Jalali jalaliDate = event.date.toJalali();
    final String dayName = jalaliDate.formatter.wN;

    // 👈 اعمال اکستنشن روی تاریخ و ساعت
    final String dateString =
        '${jalaliDate.year}/${jalaliDate.formatter.m}/${jalaliDate.formatter.d}'
            .toPersianDigit(isPersian);
    final String timeString = event.time.toPersianDigit(isPersian);

    return Container(
      margin: const EdgeInsets.only(
          bottom: 12), // 👈 هماهنگی فاصله بیرونی با اپلیکیشن ۱
      padding: const EdgeInsets.all(12), // 👈 هماهنگی فاصله درونی با اپلیکیشن ۱
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.event_busy,
              color: Colors.red,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  style: const TextStyle(
                    fontFamily: 'Vazir',
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'مربوط به: ${user.name}',
                  style: TextStyle(
                    fontFamily: 'Vazir',
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined,
                        size: 14, color: AppColors.primaryBlue),
                    const SizedBox(width: 4),
                    Text(
                      '$dayName، $dateString',
                      style: TextStyle(
                        fontFamily: 'Vazir',
                        fontSize: 11,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Icon(Icons.access_time, size: 14, color: Colors.red),
                    const SizedBox(width: 4),
                    Text(
                      timeString, // 👈 متغیر ترجمه شده به فارسی
                      style: const TextStyle(
                        fontFamily: 'Vazir',
                        fontSize: 11,
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('در حال تماس با ${user.name}...',
                    style: const TextStyle(fontFamily: 'Vazir')),
                duration: const Duration(seconds: 2),
              ));
              onCallTap();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.primaryBlue,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.phone, color: Colors.white, size: 16),
                  SizedBox(width: 4),
                  Text(
                    'تماس',
                    style: TextStyle(
                      fontFamily: 'Vazir',
                      fontSize: 12,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final overdueEvents = _getOverdueEvents();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              _buildSoftButton(
                icon: Icons.notifications_none_rounded,
                onTap: onNotificationTap ??
                    () => _showOverduePopup(context, overdueEvents),
              ),
              if (overdueEvents.isNotEmpty)
                Positioned(
                  top: 2,
                  right: 2,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: Colors.red.shade600,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
            ],
          ),
          Image.asset(
            '../../../assets/images/CareMateWithoutBack.png',
            height: 55,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return const Icon(Icons.broken_image, color: Colors.grey);
            },
          ),
          GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ProfileScreen()),
            ),
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: AppColors.primaryBlue.withOpacity(0.1), width: 2),
              ),
              child: const ProfileAvatar(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSoftButton({required IconData icon, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryBlue.withOpacity(0.08),
              offset: const Offset(0, 4),
              blurRadius: 12,
            ),
          ],
        ),
        child: Icon(icon, color: Colors.black87, size: 24),
      ),
    );
  }
}
