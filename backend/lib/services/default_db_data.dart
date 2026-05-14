class DefaultDbData {
  static Map<String, dynamic> getDefaultData() {
    final now = DateTime.now();
    // تاریخ امروز
    final todayStr =
        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

    // تاریخ شروع داروها (مثلا از یک ماه پیش)
    final pastDateStr =
        now.subtract(const Duration(days: 30)).toIso8601String();

    return {
      'currentIndex': 0,
      'status': 'pending',
      'consumed': [],
      'scheduleList': [
        // ---------- داروهای مامان جون ----------
        {
          'id': 1,
          'patient': 'مامان جون',
          'type': 'med',
          'name': 'قرص متفورمین (گلوکوفاژ)',
          'details': '500 میلی‌گرم - بعد از صبحانه',
          'time': '08:00',
          'frequency': 'روزانه',
          'startDate': pastDateStr,
          'intervalDays': 1,
        },
        {
          'id': 2,
          'patient': 'مامان جون',
          'type': 'med',
          'name': 'قرص آ.اس.آ (آسپرین)',
          'details': '80 میلی‌گرم - محافظت قلبی',
          'time': '08:30',
          'frequency': 'روزانه',
          'startDate': pastDateStr,
          'intervalDays': 1,
        },
        {
          'id': 3,
          'patient': 'مامان جون',
          'type': 'med',
          'name': 'پرل ویتامین D3',
          'details': '50,000 واحد - همراه با وعده چرب',
          'time': '13:00',
          'frequency': 'دوره‌ای',
          'startDate': pastDateStr,
          'intervalDays': 30, // ماهی یک‌بار
        },
        {
          'id': 4,
          'patient': 'مامان جون',
          'type': 'med',
          'name': 'قرص متفورمین (گلوکوفاژ)',
          'details': '500 میلی‌گرم - بعد از شام',
          'time': '20:00',
          'frequency': 'روزانه',
          'startDate': pastDateStr,
          'intervalDays': 1,
        },
        {
          'id': 5,
          'patient': 'مامان جون',
          'type': 'med',
          'name': 'قرص آتورواستاتین',
          'details': '20 میلی‌گرم - کنترل چربی خون',
          'time': '22:00',
          'frequency': 'روزانه',
          'startDate': pastDateStr,
          'intervalDays': 1,
        },
        // ---------- قرارهای پزشکی مامان جون ----------
        {
          'id': 6,
          'patient': 'مامان جون',
          'type': 'appointment',
          'name': 'آزمایشگاه تشخیص طبی',
          'details': 'قند خون ناشتا (FBS) و پروفایل چربی',
          'time': '07:30',
          'frequency': 'یکباره',
          'startDate': todayStr, // جایگزین 'date' شد
          'intervalDays': null, // این خط اضافه شد
        },
        {
          'id': 7,
          'patient': 'مامان جون',
          'type': 'appointment',
          'name': 'ملاقات با متخصص قلب',
          'details': 'چکاپ دوره‌ای - همراه داشتن جواب آزمایش و نوار قلب',
          'time': '17:30',
          'frequency': 'یکباره',
          'startDate': todayStr, // جایگزین 'date' شد
          'intervalDays': null, // این خط اضافه شد
        },
        // ---------- سایر افراد (بابا جون و سارا) ----------
        {
          'id': 8,
          'patient': 'بابا جون',
          'type': 'med',
          'name': 'قرص لوزارتان',
          'details': '50 میلی‌گرم - کنترل فشار خون',
          'time': '09:00',
          'frequency': 'روزانه',
          'startDate': pastDateStr,
          'intervalDays': 1,
        },
        {
          'id': 9,
          'patient': 'سارا',
          'type': 'med',
          'name': 'شربت مولتی‌ویتامین',
          'details': '۵ سی‌سی',
          'time': '15:00',
          'frequency': 'روزانه',
          'startDate': pastDateStr,
          'intervalDays': 1,
        },
      ],
    };
  }
}
