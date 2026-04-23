import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/notification_provider.dart';
import '../theme/app_style.dart'; // حاوی AppColors و AppTextStyles

class CustomHeader extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final TextStyle font;
  final VoidCallback onProfileTap;
  final VoidCallback? onNotificationTap;

  const CustomHeader({
    Key? key,
    required this.title,
    required this.font,
    required this.onProfileTap,
    this.onNotificationTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final hasUnread = context.watch<NotificationProvider>().hasUnread;

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 10.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            GestureDetector(
              onTap: onNotificationTap,
              child: _neumorphicContainer(
                padding: 10,
                child: Stack(
                  children: [
                    Icon(Icons.notifications_none_rounded,
                        color: AppColors.textPrimary, size: 24), // آپدیت رنگ
                    if (hasUnread)
                      Positioned(
                        right: 0,
                        top: 0,
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
              ),
            ),
            Text(
              title,
              style: font.copyWith(
                  fontSize: 24, color: AppColors.textPrimary), // آپدیت رنگ
            ),
            GestureDetector(
              onTap: onProfileTap,
              child: _neumorphicContainer(
                padding: 3,
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor:
                      AppColors.primary.withOpacity(0.2), // آپدیت رنگ
                  child:
                      Icon(Icons.person, color: AppColors.primary), // آپدیت رنگ
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _neumorphicContainer({required Widget child, double padding = 8}) {
    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: AppColors.background,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
              color: AppColors.shadowLight,
              offset: const Offset(-4, -4),
              blurRadius: 10),
          BoxShadow(
              color: AppColors.shadowDark,
              offset: const Offset(4, 4),
              blurRadius: 10),
        ],
      ),
      child: child,
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(80.0);
}
