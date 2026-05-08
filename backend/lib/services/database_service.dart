import 'dart:convert';
import 'dart:io';

class DatabaseService {
  static const String _filePath = 'db.json';

  // داده‌های اولیه به‌روزرسانی شده با داروهای بیشتر برای مادر
  static final Map<String, dynamic> _defaultData = {
    'currentIndex': 0,
    'scheduleList': [
      {
        'id': 1,
        'patient': 'مامان جون',
        'type': 'med',
        'name': 'قرص آسپرین',
        'details': '80 میلی گرم',
        'time': '08:00',
        'frequency': 'روزانه'
      },
      {
        'id': 2,
        'patient': 'مامان جون',
        'type': 'med',
        'name': 'کپسول ویتامین دی',
        'details': '50000 واحد',
        'time': '10:00',
        'frequency': 'هفتگی'
      },
      {
        'id': 6,
        'patient': 'بابا جون',
        'type': 'appointment',
        'name': 'وقت دکتر دیابت',
        'details': 'چکاپ ماهانه',
        'time': '13:45',
        'frequency': 'یکباره'
      },
      {
        'id': 3,
        'patient': 'مامان جون',
        'type': 'med',
        'name': 'قرص پلاویکس',
        'details': '75 میلی گرم',
        'time': '14:00',
        'frequency': 'روزانه'
      },
      {
        'id': 4,
        'patient': 'مامان جون',
        'type': 'appointment',
        'name': 'ملاقات با دکتر قلب',
        'details': 'چکاپ دوره‌ای - همراه داشتن نوار قلب فراموش نشود',
        'time': '17:30',
        'frequency': 'تاریخ مقرر'
      },
      {
        'id': 7,
        'patient': 'سارا',
        'type': 'med',
        'name': 'شربت ویتامین',
        'details': '۵ سی‌سی',
        'time': '18:00',
        'frequency': 'روزانه'
      },
      {
        'id': 5,
        'patient': 'مامان جون',
        'type': 'med',
        'name': 'قرص آتورواستاتین',
        'details': '20 میلی گرم',
        'time': '19:45',
        'frequency': 'روزانه'
      },
      {
        'id': 7,
        'patient': 'سارا',
        'type': 'appointment',
        'name': 'نوبت پزشک',
        'details': 'چکاپ 6 ماهگی',
        'time': '20:15',
        'frequency': 'تاریخ مقرر'
      },
    ],
    'status': 'pending',
    'consumed': [],
  };

  Future<Map<String, dynamic>> readData() async {
    final file = File(_filePath);
    if (!await file.exists()) {
      await writeData(_defaultData);
      return _defaultData;
    }
    final content = await file.readAsString();
    return jsonDecode(content);
  }

  Future<void> writeData(Map<String, dynamic> data) async {
    final file = File(_filePath);
    await file.writeAsString(jsonEncode(data));
  }
}
