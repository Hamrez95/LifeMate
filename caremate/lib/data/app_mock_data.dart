// lib/data/app_mock_data.dart

import '../models/user_model.dart';
import '../models/event_model.dart';

class MockData {
  static const String patientNameEn = "John Doe";
  static const String pregnancyWeek = "12";
  static const String medicationProgress = "80%";
  static const double medicationProgressValue = 0.8;
  static const double partnerStatusValue = 0.75;
}

class AppMockData {
  static List<UserModel> familyMembers = [
    UserModel(
        id: 'u1',
        name: 'مریم',
        role: 'مادر',
        avatarPath: '../../assets/images/mother_avatar.png'),
    UserModel(
        id: 'u2',
        name: 'علی',
        role: 'پدر',
        avatarPath: '../../assets/images/father_avatar.png'),
    UserModel(
        id: 'u3',
        name: 'سارا',
        role: 'فرزند',
        avatarPath: '../../assets/images/child_avatar.png'),
  ];

  static final DateTime _today =
      DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  static final String _pastTime =
      '${(DateTime.now().hour - 2).toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}';

  // <<< منطق هوشمند تولید رویدادهای تکرارشونده >>>
  static List<EventModel> get calendarEvents {
    final List<EventModel> generatedEvents = [];
    final Map<String, Map<DateTime, bool>> completionData =
        _getCompletionData();

    for (final template in _eventTemplates) {
      // اگر رویداد تکراری نیست، فقط خود آن را اضافه کن
      if (template.repeatIntervalInDays == null ||
          template.repeatIntervalInDays == 0) {
        generatedEvents.add(template);
        continue;
      }

      // اگر رویداد تکراری است، آن را برای یک بازه زمانی تولید کن
      // (مثلا از ۳۰ روز قبل تا ۶۰ روز آینده)
      for (int i = -30; i < 60; i++) {
        DateTime currentDate = template.date.add(Duration(days: i));

        // بررسی اینکه آیا این روز در الگوی تکرار صدق می‌کند
        if (currentDate.isAfter(template.date) &&
            currentDate.difference(template.date).inDays %
                    template.repeatIntervalInDays! ==
                0) {
          // بررسی تاریخ پایان (اگر وجود دارد)
          if (template.endDate != null &&
              currentDate.isAfter(template.endDate!)) {
            break;
          }

          // وضعیت انجام کار برای این روز خاص
          final bool? status = completionData[template.id]?[currentDate];

          generatedEvents.add(
              template.copyWith(newDate: currentDate, newIsCompleted: status));
        }
      }
    }
    return generatedEvents;
  }

  // داده‌های وضعیت انجام کار برای رویدادهای مختلف در روزهای مختلف
  static Map<String, Map<DateTime, bool>> _getCompletionData() {
    return {
      'e1': {
        // آسپرین مادر
        _today.subtract(const Duration(days: 2)): true, // دو روز پیش انجام شده
        _today.subtract(const Duration(days: 1)): false, // دیروز انجام نشده
      },
      'e4': {
        // تست قند خون پدر
        _today.subtract(const Duration(days: 2)):
            false, // دو روز پیش انجام نشده
      }
    };
  }

  // الگوهای رویدادها (تکی و تکرارشونده)
  static final List<EventModel> _eventTemplates = [
    // === رویدادهای مادر (بیماری قلبی) ===
    EventModel(
      // داروی روزانه
      id: 'e1', userId: 'u1', title: 'قرص آسپرین',
      type: EventType.medicine,
      date: _today.subtract(const Duration(days: 10)), // از ۱۰ روز پیش شروع شده
      time: '08:00', description: 'بعد از صبحانه',
      repeatIntervalInDays: 1, // هر روز
    ),
    EventModel(
      // داروی فراموش شده امروز
      id: 'e2', userId: 'u1', title: 'قرص پلاویکس (قلب)',
      type: EventType.medicine, date: _today, time: _pastTime,
      description: 'بسیار مهم',
      isCompleted: false, // این یک رویداد تکی برای امروز است
    ),
    EventModel(
      // ویزیت یکباره در آینده
      id: 'e3', userId: 'u1', title: 'ویزیت متخصص قلب',
      type: EventType.doctor, date: _today.add(const Duration(days: 2)),
      time: '16:30', description: 'همراه با نوار قلب جدید',
    ),

    // === رویدادهای پدر (دیابت) ===
    EventModel(
      // چکاپ هر دو روز یکبار
      id: 'e4', userId: 'u2', title: 'تست قند خون ناشتا',
      type: EventType.checkup, date: _today.subtract(const Duration(days: 15)),
      time: '07:00', description: 'ثبت در دفترچه',
      repeatIntervalInDays: 2, // هر ۲ روز
    ),
    EventModel(
      // داروی فراموش شده روزانه
      id: 'e5', userId: 'u2', title: 'تزریق انسولین',
      type: EventType.medicine, date: _today, time: _pastTime,
      description: 'قبل از ناهار', isCompleted: false, // رویداد تکی برای امروز
    ),
    EventModel(
      // داروی روزانه آینده
      id: 'e6', userId: 'u2', title: 'قرص متفورمین',
      type: EventType.medicine, date: _today.subtract(const Duration(days: 20)),
      time: '20:00', description: 'همراه با شام',
      repeatIntervalInDays: 1, // هر روز
    ),

    // === رویدادهای فرزند ===
    EventModel(
      // مکمل هفتگی
      id: 'e7', userId: 'u3', title: 'شربت مولتی ویتامین',
      type: EventType.medicine, date: _today.subtract(const Duration(days: 14)),
      time: '10:00', description: 'فقط جمعه‌ها',
      repeatIntervalInDays: 7, // هر ۷ روز (هفتگی)
    ),
    EventModel(
      // رویداد تکی
      id: 'e8', userId: 'u3', title: 'چکاپ دندانپزشکی',
      type: EventType.checkup, date: _today.add(const Duration(days: 5)),
      time: '10:00', description: 'کلینیک لبخند',
    ),
  ];
}
