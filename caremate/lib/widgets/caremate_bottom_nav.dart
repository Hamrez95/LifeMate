import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/localization/app_localizations.dart'; // مسیرها را چک کنید
import '../../core/localization/locale_provider.dart';
import '../core/constants/app_colors.dart';

class CareMateBottomNav extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const CareMateBottomNav({
    Key? key,
    required this.currentIndex,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
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
              color: AppColors.primaryBlue
                  .withOpacity(0.08), // سایه نرم و هماهنگ با تم اپ
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildNavItem(
              icon: Icons.calendar_month_rounded,
              label: loc['nav_calendar'] ?? 'تقویم',
              index: 0,
              fontFamily: fontFamily,
            ),
            _buildNavItem(
              icon: Icons.switch_account_rounded,
              label: loc['nav_profiles'] ?? 'تغییر پروفایل',
              index: 1,
              fontFamily: fontFamily,
            ),
            // دکمه افزودن حالا به شکل مینیمال و هماهنگ درآمده است
            _buildNavItem(
              icon: Icons.medical_services,
              label: loc['nav_add_new_threadment'] ?? 'مدیریت درمان',
              index: 2,
              fontFamily: fontFamily,
            ),
            _buildNavItem(
              icon: Icons.family_restroom_rounded,
              label: loc['nav_caring'] ?? 'مراقبت',
              index: 3,
              fontFamily: fontFamily,
            ),
            _buildNavItem(
              icon: Icons.home_rounded,
              label: loc['nav_home'] ?? 'خانه', // داشبورد
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
    final color = isSelected
        ? AppColors.primaryBlue
        : AppColors.secondaryText.withOpacity(0.5);

    return GestureDetector(
      onTap: () => onTap(index),
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize
            .min, // باعث می‌شود ارتفاع دکمه فقط به اندازه محتوا باشد
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
