import 'package:flutter/material.dart';

class AppColors {
  static const Color background =
      Color(0xFFF4F9F6); // یک سبز-مینت بسیار روشن و فرِش
  static const Color primary =
      Color(0xFF10B981); // سبز زمردی زنده و درخشان (مثل CareMate)
  static const Color primaryLight = Color(0xFF34D399);

  static const Color textPrimary = Color(0xFF1F2937); // متن تیره مدرن
  static const Color textSecondary = Color(0xFF6B7280);

  static const Color white = Colors.white;
  static const Color shadowLight = Colors.white;
  static const Color shadowDark = Color(0xFFD1E0D7); // سایه نرم برای کارت‌ها

  static const Color success = Color(0xFF10B981);
  static const Color cardBackground = Colors.white;

  static const Color primaryBlue = Color(0xFF4A90E2);
  static const Color darkBlue = Color(0xFF283054); // رنگ سرمه‌ای (متن‌های اصلی)
  static const Color avatarBackground =
      Color(0xFFE2D4C8); // رنگ پس‌زمینه آواتار
  // رنگ پس‌زمینه کارت‌ها و کادرها
  static const Color secondaryText = Color(0xFF7B93DB); // متن‌های ثانویه

  static const Color textMain = Color(0xFF283054);
  // سایه تیره (برای ایجاد عمق در طراحی نئومورفیک)
  static const Color shadow =
      Color(0x14000000); // معادل Colors.black.withOpacity(0.08)
  // سایه روشن (برای ایجاد برجستگی در طراحی نئومورفیک)
  static const Color lightShadow = Colors.white;

  // --- رنگ‌های مخصوص تقویم ---
  static const Color calOverdueBack =
      Color(0xFFFFEBEE); // پس‌زمینه روزهای فراموش شده
  static const Color calDotMedicine = Colors.pinkAccent;
  static const Color calDotDoctor = Colors.blueAccent;
  static const Color calDotTreatment = Colors.orangeAccent;
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
