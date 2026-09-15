import 'package:lifemate_client/lifemate_client.dart';
import 'package:shamsi_date/shamsi_date.dart';

/// افزونه‌ای برای تبدیل شماره روز هفته به نام فارسی آن
extension PersianDayNameExtension on Jalali {
  /// نام فارسی روز هفته را برمی‌گرداند (مثال: 'شنبه')
  String get persianDayName => _localizedDayName(weekDay);
}

/// (اختیاری) اگر بخواهید مستقیما روی اعداد (int) هم این قابلیت را داشته باشید
extension IntPersianDayExtension on int {
  String get toPersianDayName => _localizedDayName(this);
}

String _localizedDayName(int day) {
  final isPersian = LifeMateRuntimeLocale.isPersian;
  switch (day) {
    case 1:
      return isPersian ? 'شنبه' : 'Saturday';
    case 2:
      return isPersian ? 'یکشنبه' : 'Sunday';
    case 3:
      return isPersian ? 'دوشنبه' : 'Monday';
    case 4:
      return isPersian ? 'سه‌شنبه' : 'Tuesday';
    case 5:
      return isPersian ? 'چهارشنبه' : 'Wednesday';
    case 6:
      return isPersian ? 'پنجشنبه' : 'Thursday';
    case 7:
      return isPersian ? 'جمعه' : 'Friday';
    default:
      return '';
  }
}
