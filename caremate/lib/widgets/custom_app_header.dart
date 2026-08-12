import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../screens/profile_screen.dart';

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

  /// Kept temporarily for source compatibility with the remaining CareMate
  /// surfaces. Account sign-out intentionally lives only as the final action
  /// on the profile page.
  final VoidCallback? onSignOutTap;
  final bool showNotificationDot;

  void _openProfile(BuildContext context) {
    final callback = onProfileTap;
    if (callback != null) {
      callback();
      return;
    }
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const ProfileScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              _SoftHeaderButton(
                tooltip: LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'هشدارهای مراقبتی',
                    en: "Careful warnings",
                  ),
                  en: "Careful warnings",
                ),
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
              errorBuilder: (_, __, ___) => Icon(
                Icons.health_and_safety_rounded,
                size: 44,
                color: AppColors.primaryBlue,
              ),
            ),
          ),
          Semantics(
            button: true,
            label: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'بازکردن پروفایل',
                en: "Open profile",
              ),
              en: "Open profile",
            ),
            child: Tooltip(
              message: LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(fa: 'پروفایل', en: "Profile"),
                en: "Profile",
              ),
              child: Material(
                color: Colors.transparent,
                shape: CircleBorder(),
                child: InkWell(
                  onTap: () => _openProfile(context),
                  customBorder: CircleBorder(),
                  child: Container(
                    padding: EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.78),
                      border: Border.all(
                        color: AppColors.primaryBlue.withValues(alpha: 0.16),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primaryBlue.withValues(alpha: 0.10),
                          blurRadius: 14,
                          offset: Offset(0, 5),
                        ),
                      ],
                    ),
                    child: LifeMateCurrentUserAvatar(
                      apiClient: context.read<LifeMateApiClient>(),
                      radius: 22,
                    ),
                  ),
                ),
              ),
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
                  color: AppColors.primaryBlue.withValues(alpha: 0.08),
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
