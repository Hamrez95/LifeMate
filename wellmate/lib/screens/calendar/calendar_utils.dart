import 'package:flutter/material.dart';
import 'package:wellmate/core/theme/app_style.dart';

class CalendarUtils {
  static IconData getIconForType(String type) {
    switch (type) {
      case 'doctor':
      case 'appointment': // <--- اضافه شد
        return Icons.person;
      case 'treatment':
        return Icons.medical_services;
      case 'medicine':
      case 'med': // <--- اضافه شد
      default:
        return Icons.medication;
    }
  }

  static Color getColorForType(String type) {
    switch (type) {
      case 'doctor':
      case 'appointment': // <--- اضافه شد
        return AppColors.calDotDoctor; // (معمولا رنگ آبی در تم شماست)
      case 'treatment':
        return AppColors.calDotTreatment;
      case 'medicine':
      case 'med': // <--- اضافه شد
        return AppColors.calDotMedicine;
      default:
        return AppColors.primary;
    }
  }
}
