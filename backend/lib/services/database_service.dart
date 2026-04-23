import 'dart:convert';
import 'dart:io';

class DatabaseService {
  static const String _filePath = 'db.json';

  // داده‌های اولیه (CareMate)
  static final Map<String, dynamic> _defaultData = {
    'currentIndex': 0,
    'scheduleList': [
      {
        'id': 1,
        'type': 'med',
        'name': 'قرص آهسته رهش دیلیست',
        'details': '30 میلی گرم',
        'time': '08:00',
        'frequency': 'روزانه'
      },
      {
        'id': 2,
        'type': 'med',
        'name': 'قرص لوزارتان',
        'details': '25 میلی گرم',
        'time': '08:00',
        'frequency': 'روزانه'
      },
      {
        'id': 3,
        'type': 'med',
        'name': 'قرص هیدروکلروتیازید',
        'details': '50 میلی گرم',
        'time': '08:00',
        'frequency': 'روزانه'
      },
      {
        'id': 4,
        'type': 'therapy',
        'name': 'فیزیوتراپی',
        'details': 'جلسه درمانی',
        'time': '16:00',
        'frequency': 'یک روز در میان'
      },
      {
        'id': 5,
        'type': 'med',
        'name': 'قرص آتورواستاتین',
        'details': '10 میلی گرم',
        'time': '21:00',
        'frequency': 'روزانه'
      },
      {
        'id': 6,
        'type': 'appointment',
        'name': 'ملاقات با دکتر',
        'details': 'فراموش نشود!',
        'time': '11:00',
        'frequency': '10 می'
      },
    ],
    'status': 'pending',
    'consumed': [],
  };

  // خواندن اطلاعات از فایل
  Future<Map<String, dynamic>> readData() async {
    final file = File(_filePath);
    if (!await file.exists()) {
      await writeData(_defaultData);
      return _defaultData;
    }
    final content = await file.readAsString();
    return jsonDecode(content);
  }

  // ذخیره اطلاعات در فایل
  Future<void> writeData(Map<String, dynamic> data) async {
    final file = File(_filePath);
    await file.writeAsString(jsonEncode(data));
  }
}
