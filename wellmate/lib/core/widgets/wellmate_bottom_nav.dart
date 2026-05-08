import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wellmate/localization/app_localizations.dart';
import 'package:wellmate/localization/locale_provider.dart';
import '../theme/app_style.dart'; // حاوی AppColors

class WellMateBottomNav extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const WellMateBottomNav({
    Key? key,
    required this.currentIndex,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // فرض بر این است که سیستم بومی‌سازی شما مشابه CareMate است
    final loc = AppLocalizations.of(context);
    final isPersian =
        Provider.of<LocaleProvider>(context).locale.languageCode == 'fa';
    final String fontFamily = isPersian ? 'Vazir' : 'Poppins';

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(35),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.08), // سایه نرم و هماهنگ
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        // در چیدمان RTL، اولین فرزند در سمت راست‌ترین حالت قرار می‌گیرد.
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // سمت راست: تقویم
            _buildNavItem(
              icon: Icons.calendar_month_rounded,
              label: loc['nav_calendar'] ?? 'تقویم',
              index: 0,
              fontFamily: fontFamily,
            ),
            // کنار تقویم: داروها
            _buildNavItem(
              icon: Icons.medication_rounded,
              label: loc['nav_medications'] ?? 'داروها',
              index: 1,
              fontFamily: fontFamily,
            ),
            // مرکز: افزودن درمان
            _buildNavItem(
              icon: Icons.add_circle_outline_rounded,
              label: loc['nav_add_treatment'] ?? 'افزودن درمان',
              index: 2,
              fontFamily: fontFamily,
            ),
            // کنار دکمه افزودن: افزودن مراقب
            _buildNavItem(
              icon: Icons.person_add_alt_1_rounded,
              label: loc['nav_add_caregiver'] ?? 'مراقب جدید',
              index: 3,
              fontFamily: fontFamily,
            ),
            // سمت چپ: خانه
            _buildNavItem(
              icon: Icons.home_rounded,
              label: loc['nav_home'] ?? 'خانه',
              index: 4,
              fontFamily: fontFamily,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required String label,
    required int index,
    required String fontFamily,
  }) {
    final isSelected = currentIndex == index;
    // از رنگ پرایمری ول‌میت استفاده می‌کنیم
    final color = isSelected
        ? AppColors.primary
        : Colors.grey.shade400; // رنگ خنثی برای آیتم‌های غیرفعال

    return GestureDetector(
      onTap: () => onTap(index),
      behavior: HitTestBehavior.opaque,
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
            style: TextStyle(
              fontFamily: fontFamily,
              fontSize: 10,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
