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
        return AppColors.calDotDoctor;
      case 'injection':
        return const Color(0xFFE97786);
      case 'treatment':
        return AppColors.calDotTreatment;
      case 'medicine':
      case 'med':
        return AppColors.calDotMedicine;
      default:
        return AppColors.primary;
    }
  }
}
