import 'package:flutter/material.dart';
import 'package:wellmate/core/theme/app_style.dart';

class CalendarUtils {
  static IconData getIconForType(String type) {
    switch (type) {
      case 'doctor':
        return Icons.person;
      case 'treatment':
        return Icons.medical_services;
      case 'medicine':
      default:
        return Icons.medication;
    }
  }

  static Color getColorForType(String type) {
    switch (type) {
      case 'doctor':
        return AppColors.calDotDoctor;
      case 'treatment':
        return AppColors.calDotTreatment;
      case 'medicine':
        return AppColors.calDotMedicine;
      default:
        return AppColors.primary;
    }
  }
}
