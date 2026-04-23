import 'package:flutter/material.dart';

class AppColors {
  static const Color background = Color(0xFFF3F6FA); // رنگ پس‌زمینه اصلی
  // رنگ اصلی (برای آیکون‌ها، دکمه‌ها و متن‌های ثانویه)
  static const Color primary =
      Color(0xFF6B8BFF); // رنگ دکمه‌ها و المان‌های اصلی
  static const Color textPrimary = Color(0xFF2D3142);
  static const Color textSecondary = Color(0xFF9098B1);
  static const Color white = Colors.white;
  static const Color shadowLight = Colors.white;
  static const Color shadowDark = Color(0xFFD6E0F0);
  static const Color success = Color(0xFF4CAF50);
  // رنگ پس‌زمینه کارت‌ها و کادرها
  static const Color cardBackground = Colors.white;
  // رنگ اصلی متن‌ها (سرمه‌ای تیره برای خوانایی بهتر)
  static const Color textMain = Color(0xFF283054);
  // سایه تیره (برای ایجاد عمق در طراحی نئومورفیک)
  static const Color shadow =
      Color(0x14000000); // معادل Colors.black.withOpacity(0.08)
  // سایه روشن (برای ایجاد برجستگی در طراحی نئومورفیک)
  static const Color lightShadow = Colors.white;
}

class AppTextStyles {
  // تشخیص خودکار فونت بر اساس زبان
  static String _getFontFamily(BuildContext context) {
    final isFa = Localizations.localeOf(context).languageCode == 'fa';
    return isFa
        ? 'Vazir'
        : 'Nunito'; // حتما این فونت‌ها باید در pubspec.yaml تعریف شده باشند
  }

  static TextStyle heading(BuildContext context) {
    return TextStyle(
      fontFamily: _getFontFamily(context),
      fontSize: 24,
      fontWeight: FontWeight.bold,
      color: AppColors.textPrimary,
    );
  }

  static TextStyle button(BuildContext context) {
    return body(context).copyWith(
      fontSize: 14,
      fontWeight: FontWeight.bold,
    );
  }

  static TextStyle body(BuildContext context) {
    return TextStyle(
      fontFamily: _getFontFamily(context),
      fontSize: 16,
      fontWeight: FontWeight.normal,
      color: AppColors.textPrimary,
    );
  }

  static TextStyle caption(BuildContext context) {
    return TextStyle(
      fontFamily: _getFontFamily(context),
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: AppColors.textSecondary,
    );
  }

  // متد کمکی برای ساخت استایل‌های کاستوم و جلوگیری از ارور
  static TextStyle get(BuildContext context,
      {Color? color, FontWeight? fontWeight, double? fontSize}) {
    return TextStyle(
      fontFamily: _getFontFamily(context),
      color: color ?? AppColors.textPrimary,
      fontWeight: fontWeight ?? FontWeight.normal,
      fontSize: fontSize ?? 16,
    );
  }
}
