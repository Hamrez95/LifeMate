import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../localization/locale_provider.dart';

class AppColors {
  static const Color bgLight = Color(0xFFF2F4F8);
  static const Color primaryText = Color(0xFF2B3A60);
  static const Color secondaryText = Color(0xFF6B7280);
  static const Color accentBlue = Color(0xFF7B93DB);
  static const Color textGrey = Color(0xFF9EA3B0);
  
  // رنگ‌های نئومورفیسم
  static Color shadowLight = Colors.white;
  static Color shadowDark = Colors.black.withOpacity(0.08);
}

class AppTextStyles {
  // این تابع به صورت خودکار فونت مناسب را بر اساس زبان انتخاب می‌کند
  static TextStyle get(BuildContext context, {
    double fontSize = 14, 
    FontWeight fontWeight = FontWeight.normal, 
    Color? color
  }) {
    final localeProvider = Provider.of<LocaleProvider>(context, listen: false);
    final isPersian = localeProvider.locale.languageCode == 'fa';
    final finalColor = color ?? AppColors.primaryText;

    if (isPersian) {
      return TextStyle(
        fontFamily: 'Vazir', 
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: finalColor,
      );
    } else {
       return TextStyle(
        fontFamily: 'Poppins', 
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: finalColor,
      );
    }
  }

  // استایل‌های آماده برای راحتی کار
  static TextStyle title(BuildContext context) => get(context, fontSize: 24, fontWeight: FontWeight.bold, color: const Color(0xFF33416E));
  static TextStyle header(BuildContext context) => get(context, fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.secondaryText);
  static TextStyle body(BuildContext context) => get(context, fontSize: 14, color: AppColors.textGrey);
}
