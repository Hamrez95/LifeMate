import 'package:shamsi_date/shamsi_date.dart';

/// افزونه‌ای برای تبدیل شماره روز هفته به نام فارسی آن
extension PersianDayNameExtension on Jalali {
  /// نام فارسی روز هفته را برمی‌گرداند (مثال: 'شنبه')
  String get persianDayName {
    switch (weekDay) {
      case 1:
        return 'شنبه';
      case 2:
        return 'یکشنبه';
      case 3:
        return 'دوشنبه';
      case 4:
        return 'سه‌شنبه';
      case 5:
        return 'چهارشنبه';
      case 6:
        return 'پنجشنبه';
      case 7:
        return 'جمعه';
      default:
        return '';
    }
  }
}

/// (اختیاری) اگر بخواهید مستقیما روی اعداد (int) هم این قابلیت را داشته باشید
extension IntPersianDayExtension on int {
  String get toPersianDayName {
    switch (this) {
      case 1:
        return 'شنبه';
      case 2:
        return 'یکشنبه';
      case 3:
        return 'دوشنبه';
      case 4:
        return 'سه‌شنبه';
      case 5:
        return 'چهارشنبه';
      case 6:
        return 'پنجشنبه';
      case 7:
        return 'جمعه';
      default:
        return '';
    }
  }
}
