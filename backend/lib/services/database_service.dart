import 'dart:convert';
import 'dart:io';

class DatabaseService {
  static const String _filePath = 'db.json';

  // داده‌های اولیه (CareMate) به‌روزرسانی شده
  static final Map<String, dynamic> _defaultData = {
    'currentIndex': 0,
    'scheduleList': [
      {
        'id': 1,
        'type': 'med',
        'name': 'قرص آسپرین',
        'details': '80 میلی گرم',
        'time': '08:00',
        'frequency': 'روزانه'
      },
      {
        'id': 2,
        'type': 'med',
        'name': 'قرص پلاویکس',
        'details': '75 میلی گرم',
        'time': '14:00',
        'frequency': 'روزانه'
      },
      {
        'id': 3,
        'type': 'appointment',
        'name': 'ملاقات با دکتر قلب',
        'details': 'چکاپ دوره‌ای - همراه داشتن نوار قلب فراموش نشود',
        'time': '17:30',
        'frequency': 'تاریخ مقرر'
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
