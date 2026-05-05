import 'package:flutter/material.dart';
import '../../localization/app_localizations.dart';
import '../theme/app_style.dart'; // مسیر صحیح AppColors و AppTextStyles خود را چک کنید

class SimpleBottomNav extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const SimpleBottomNav({
    Key? key,
    required this.currentIndex,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final font = AppTextStyles.body(context);

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.cardBackground, // ترجیحاً رنگ سفید یا پس‌زمینه کارت
          borderRadius: BorderRadius.circular(35),
          boxShadow: [
            BoxShadow(
              color: AppColors.shadowDark.withOpacity(0.08), // سایه بسیار نرم
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _navItem(
              icon: Icons.calendar_today_rounded,
              label: loc['nav_calendar'] ?? 'تقویم',
              isActive: currentIndex == 0,
              onTap: () => onTap(0),
              font: font,
            ),
            _navItem(
              icon: Icons.home_filled,
              label: loc['nav_home'] ?? 'خانه',
              isActive: currentIndex == 1,
              onTap: () => onTap(1),
              font: font,
            ),
            // دکمه افزودن را هم به شکل یکپارچه و مینیمال درآوردیم
            _navItem(
              icon: Icons.add_circle_outline,
              label: loc['home_add_medicine'] ?? 'افزودن',
              isActive: currentIndex == 2,
              onTap: () => onTap(2),
              font: font,
            ),
            _navItem(
              icon: Icons.person_outline,
              label: loc['nav_profile'] ?? 'پروفایل',
              isActive: currentIndex == 3,
              onTap: () => onTap(3),
              font: font,
            ),
            _navItem(
              icon: Icons.settings_outlined,
              label: loc['nav_settings'] ?? 'تنظیمات',
              isActive: currentIndex == 4,
              onTap: () => onTap(4),
              font: font,
            ),
          ],
        ),
      ),
    );
  }

  Widget _navItem({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
    required TextStyle font,
  }) {
    // رنگ آیتم فعال (بنفش/اصلی) و غیرفعال (خاکستری)
    final color = isActive ? AppColors.primary : AppColors.textSecondary;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior
          .opaque, // برای اینکه کل فضای بین آیکون و متن قابل کلیک باشد
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 26,
            color: color,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: font.copyWith(
              fontSize: 10,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
