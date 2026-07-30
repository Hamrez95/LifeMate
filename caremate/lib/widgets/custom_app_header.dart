import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../screens/profile_screen.dart';
import 'custom_ui_components.dart';

class CustomAppHeader extends StatelessWidget {
  const CustomAppHeader({
    super.key,
    this.onNotificationTap,
    this.onProfileTap,
    this.onSignOutTap,
    this.showNotificationDot = false,
  });

  final VoidCallback? onNotificationTap;
  final VoidCallback? onProfileTap;
  final VoidCallback? onSignOutTap;
  final bool showNotificationDot;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              _SoftHeaderButton(
                tooltip: 'هشدارهای مراقبتی',
                icon: Icons.notifications_none_rounded,
                onTap: onNotificationTap,
              ),
              if (showNotificationDot)
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
          Semantics(
            label: 'CareMate',
            image: true,
            child: Image.asset(
              'assets/images/CareMateWithoutBack.png',
              height: 55,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.health_and_safety_rounded,
                size: 44,
                color: AppColors.primaryBlue,
              ),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'حساب کاربری',
            color: Colors.white,
            elevation: 10,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            onSelected: (value) {
              if (value == 'profile') {
                final callback = onProfileTap;
                if (callback != null) {
                  callback();
                } else {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ProfileScreen()),
                  );
                }
              } else if (value == 'sign_out') {
                onSignOutTap?.call();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'profile',
                child: Row(
                  children: [
                    Icon(Icons.person_outline_rounded,
                        color: AppColors.primaryBlue),
                    SizedBox(width: 10),
                    Text('پروفایل'),
                  ],
                ),
              ),
              if (onSignOutTap != null)
                const PopupMenuItem(
                  value: 'sign_out',
                  child: Row(
                    children: [
                      Icon(Icons.logout_rounded, color: Colors.redAccent),
                      SizedBox(width: 10),
                      Text('خروج از حساب'),
                    ],
                  ),
                ),
            ],
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.primaryBlue.withOpacity(0.14),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryBlue.withOpacity(0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const ProfileAvatar(),
            ),
          ),
        ],
      ),
    );
  }
}

class _SoftHeaderButton extends StatelessWidget {
  const _SoftHeaderButton({
    required this.tooltip,
    required this.icon,
    this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
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
        ),
      ),
    );
  }
}
