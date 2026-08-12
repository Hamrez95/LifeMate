import 'package:shamsi_date/shamsi_date.dart';
import 'package:lifemate_client/lifemate_client.dart';

/// افزونه‌ای برای تبدیل شماره روز هفته به نام فارسی آن
extension PersianDayNameExtension on Jalali {
  /// نام فارسی روز هفته را برمی‌گرداند (مثال: 'شنبه')
  String get persianDayName {
    switch (weekDay) {
      case 1:
        return LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(fa: 'شنبه', en: "Saturday"),
          en: "Saturday",
        );
      case 2:
        return LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(fa: 'یکشنبه', en: "Sunday"),
          en: "Sunday",
        );
      case 3:
        return LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(fa: 'دوشنبه', en: "Monday"),
          en: "Monday",
        );
      case 4:
        return LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(fa: 'سه‌شنبه', en: "Tuesday"),
          en: "Tuesday",
        );
      case 5:
        return LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(fa: 'چهارشنبه', en: "Wednesday"),
          en: "Wednesday",
        );
      case 6:
        return LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(fa: 'پنجشنبه', en: "Thursday"),
          en: "Thursday",
        );
      case 7:
        return LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(fa: 'جمعه', en: "Friday"),
          en: "Friday",
        );
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
        return LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(fa: 'شنبه', en: "Saturday"),
          en: "Saturday",
        );
      case 2:
        return LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(fa: 'یکشنبه', en: "Sunday"),
          en: "Sunday",
        );
      case 3:
        return LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(fa: 'دوشنبه', en: "Monday"),
          en: "Monday",
        );
      case 4:
        return LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(fa: 'سه‌شنبه', en: "Tuesday"),
          en: "Tuesday",
        );
      case 5:
        return LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(fa: 'چهارشنبه', en: "Wednesday"),
          en: "Wednesday",
        );
      case 6:
        return LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(fa: 'پنجشنبه', en: "Thursday"),
          en: "Thursday",
        );
      case 7:
        return LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(fa: 'جمعه', en: "Friday"),
          en: "Friday",
        );
      default:
        return '';
    }
  }
}
