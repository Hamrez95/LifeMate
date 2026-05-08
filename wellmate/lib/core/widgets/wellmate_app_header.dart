import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/notification_provider.dart';
import '../theme/app_style.dart'; // حاوی AppColors

class WellMateAppHeader extends StatelessWidget {
  final VoidCallback onProfileTap;
  final VoidCallback? onNotificationTap;

  const WellMateAppHeader({
    Key? key,
    required this.onProfileTap,
    this.onNotificationTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final hasUnread = context.watch<NotificationProvider>().hasUnread;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // دکمه نوتیفیکیشن با دات قرمز (استایل شیشه‌ای/نرم مشابه CareMate)
          Stack(
            clipBehavior: Clip.none,
            children: [
              _buildSoftButton(
                icon: Icons.notifications_none_rounded,
                onTap: onNotificationTap,
              ),
              if (hasUnread)
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

          // لوگوی اپلیکیشن (جایگزین متن)
          Image.asset(
            '../../../assets/images/WellMateWithoutBack.png', // مسیر عکس را در صورت نیاز اصلاح کن
            height: 55,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return const Icon(Icons.broken_image, color: Colors.grey);
            },
          ),

          // دکمه پروفایل
          GestureDetector(
            onTap: onProfileTap,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: AppColors.primary.withOpacity(0.1), width: 2),
              ),
              child: CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.primary.withOpacity(0.1),
                child: Icon(Icons.person, color: AppColors.primary, size: 24),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // دکمه نرم جایگزین Neumorphic خشن قبلی
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
              color: AppColors.primary.withOpacity(0.08), // سایه بسیار ملایم
              offset: const Offset(0, 4),
              blurRadius: 12,
            ),
          ],
        ),
        child: Icon(icon, color: AppColors.textPrimary, size: 24),
      ),
    );
  }
}
