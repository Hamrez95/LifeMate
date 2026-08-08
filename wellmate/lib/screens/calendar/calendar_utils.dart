import 'package:flutter/material.dart';
import 'package:wellmate/core/theme/app_style.dart';

class CalendarUtils {
  static IconData getIconForType(String type) {
    switch (type) {
      case 'doctor':
      case 'appointment':
        return Icons.medical_services_rounded;
      case 'injection':
        return Icons.vaccines_rounded;
      case 'treatment':
        return Icons.health_and_safety_rounded;
      case 'medicine':
      case 'med':
      default:
        return Icons.medication_rounded;
    }
  }

  static Color getColorForType(String type) {
    switch (type) {
      case 'doctor':
      case 'appointment':
        return AppColors.careVisit;
      case 'injection':
        return AppColors.careInjection;
      case 'treatment':
        return AppColors.careInjection;
      case 'medicine':
      case 'med':
        return AppColors.careMedication;
      default:
        return AppColors.primary;
    }
  }
}
