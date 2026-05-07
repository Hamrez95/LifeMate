import 'package:flutter/material.dart';
import '../screens/profile_screen.dart'; // مسیرها را چک کن
import 'custom_ui_components.dart'; // مسیرها را چک کن
import '../../models/event_model.dart';
import '../../data/app_mock_data.dart';
import '../../core/constants/app_colors.dart';

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

  // ۳. نمایش پاپ‌آپ نوتیفیکیشن
  void _showOverduePopup(BuildContext context, List<EventModel> overdueEvents) {
    if (overdueEvents.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('رویداد تاخیر داری وجود ندارد',
                style: TextStyle(fontFamily: 'Vazir'))),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('یادآوری‌های تاخیر دار',
                  style: TextStyle(
                      fontFamily: 'Vazir',
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.red)),
              const SizedBox(height: 10),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: overdueEvents.length,
                  itemBuilder: (context, index) {
                    final event = overdueEvents[index];
                    final user = AppMockData.familyMembers
                        .firstWhere((u) => u.id == event.userId);
                    return ListTile(
                      title: Text('${event.title} (${user.name})',
                          style: const TextStyle(fontFamily: 'Vazir')),
                      subtitle: Text('زمان: ${event.time}',
                          style: const TextStyle(fontFamily: 'Vazir')),
                      trailing: IconButton(
                        icon: Icon(Icons.phone, color: AppColors.primaryBlue),
                        onPressed: () {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text('در حال تماس با ${user.name}...',
                                  style:
                                      const TextStyle(fontFamily: 'Vazir'))));
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

  @override
  Widget build(BuildContext context) {
    // گرفتن لیست رویدادهای فراموش شده در لحظه ساخت ویجت
    final overdueEvents = _getOverdueEvents();

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // دکمه نوتیفیکیشن با قابلیت نمایش دات قرمز
        Stack(
          clipBehavior: Clip.none,
          children: [
            GlassIconButton(
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
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),

        // لوگوی اپلیکیشن
        Image.asset(
          '../../../assets/images/CareMateWithoutBack.png', // مسیر قطعی لوگو
          height: 40,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return const Icon(Icons.broken_image, color: Colors.grey);
          },
        ),

        // دکمه پروفایل
        GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ProfileScreen()),
          ),
          child:
              const ProfileAvatar(), // فرض بر این است که ProfileAvatar ساخته شده است
        ),
      ],
    );
  }
}
