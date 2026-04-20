import 'package:flutter/material.dart';

class AppColors {
  static const Color background = Color(0xFFDFE9F5);
  static const Color primaryBlue = Color(0xFF4A90E2);
  static const Color titleDarkBlue = Color(0xFF33416E);
  static const Color glassBackground = Color(0xFFF0F4FA);
  static const Color darkBlue = Color(0xFF283054); // رنگ سرمه‌ای (متن‌های اصلی)
  static const Color primaryText = Color(0xFF2B3A60); // متن‌های تیره
  static const Color secondaryText = Color(0xFF7B93DB); // متن‌های ثانویه
  static const Color avatarBackground = Color(0xFFE2D4C8); // رنگ پس‌زمینه آواتار
  static const Color cardBackground = Colors.white; // رنگ کارت‌ها
  static const Color lightContainer = Color(0xFFF0F4FA); // کانتینرهای روشن
  
  // سایه‌ها و افکت‌های نئومورفیسم/گلس
  static BoxDecoration softDecoration({Color color = Colors.white}) {
    return BoxDecoration(
      color: color.withOpacity(0.85),
      borderRadius: BorderRadius.circular(24),
      boxShadow: [
        BoxShadow(color: Colors.white.withOpacity(0.8), offset: const Offset(-6, -6), blurRadius: 12),
        BoxShadow(color: const Color(0xFFA6BCCF).withOpacity(0.3), offset: const Offset(6, 6), blurRadius: 12),
      ],
    );
  }
}
