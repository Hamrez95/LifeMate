import 'package:flutter/material.dart';
import '../../models/schedule_item_model.dart';

class MedicationProvider extends ChangeNotifier {
  List<ScheduleItemModel> _allMedications = [];

  // دریافت تمام داروها
  List<ScheduleItemModel> get allMedications => _allMedications;

  // محاسبه خودکار داروهای فراموش شده
  List<ScheduleItemModel> get missedItems {
    final now = DateTime.now();

    return _allMedications.where((item) {
      // اگر دارو مصرف شده است، قطعا فراموش شده نیست
      if (item.isDone) return false;

      // تبدیل رشته زمان (مثلا "08:00") به آبجکت DateTime برای مقایسه دقیق
      try {
        final parts = item.time.split(':');
        if (parts.length == 2) {
          final hour = int.parse(parts[0]);
          final minute = int.parse(parts[1]);

          // ساختن یک زمان برای امروز با ساعت و دقیقه دارو
          final itemTime = DateTime(now.year, now.month, now.day, hour, minute);

          // اگر زمان مصرف گذشته باشد، true برمی‌گرداند
          return itemTime.isBefore(now);
        }
      } catch (e) {
        // در صورتی که فرمت زمان اشتباه باشد (مثلا خالی باشد)، از آن رد می‌شویم
        debugPrint("خطا در تبدیل زمان دارو: ${item.time}");
        return false;
      }

      return false;
    }).toList();
  }

  // متدی برای مقداردهی یا آپدیت لیست داروها
  void setMedications(List<ScheduleItemModel> items) {
    _allMedications = items;
    notifyListeners();
  }

  // متدی برای ثبت مصرف دارو
  void markAsDone(String id) {
    final index = _allMedications.indexWhere((item) => item.id == id);
    if (index != -1) {
      // استفاده از متد copyWith به دلیل final بودن متغیرها در مدل
      _allMedications[index] = _allMedications[index].copyWith(isDone: true);
      notifyListeners();
    }
  }
}
