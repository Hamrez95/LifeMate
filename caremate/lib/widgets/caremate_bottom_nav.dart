import 'package:flutter/material.dart';
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
    // استفاده از استایل شیشه‌ای (نئومورفیسم) که قبلا در AppColors تعریف کردیم
    return Container(
      height: 70,
      decoration: AppColors.softDecoration(color: Colors.white),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildNavItem(icon: Icons.calendar_month_rounded, index: 0),
          _buildNavItem(icon: Icons.chat_bubble_outline_rounded, index: 1),
          
          // 👈 دکمه برجسته و متفاوت در وسط (مثلاً برای افزودن گزارش جدید)
          GestureDetector(
            onTap: () => onTap(2),
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.primaryBlue,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryBlue.withOpacity(0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  )
                ],
              ),
              child: const Icon(Icons.add, color: Colors.white, size: 28),
            ),
          ),

          _buildNavItem(icon: Icons.assignment_rounded, index: 3),
          _buildNavItem(icon: Icons.home_rounded, index: 4), // 👈 داشبورد (خانه)
        ],
      ),
    );
  }

  // متد کمکی برای ساخت دکمه‌های آیکون‌دار
  Widget _buildNavItem({required IconData icon, required int index}) {
    final isSelected = currentIndex == index;
    return GestureDetector(
      onTap: () => onTap(index),
      behavior: HitTestBehavior.opaque, // برای اینکه فضای اطراف آیکون هم قابل کلیک باشد
      child: Container(
        padding: const EdgeInsets.all(12),
        child: Icon(
          icon,
          size: 28,
          color: isSelected ? AppColors.primaryBlue : AppColors.secondaryText.withOpacity(0.5),
        ),
      ),
    );
  }
}
