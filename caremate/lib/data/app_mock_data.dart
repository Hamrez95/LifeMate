import '../models/user_model.dart';
import '../models/event_model.dart';

class AppMockData {
  // ۱. لیست اعضای خانواده
  static List<UserModel> familyMembers = [
    UserModel(
      id: 'u1',
      name: 'مریم',
      role: 'مادر',
      avatarPath: 'assets/images/mother_avatar.png', // مسیر عکس‌ها را بر اساس پروژه خودت تنظیم کن
    ),
    UserModel(
      id: 'u2',
      name: 'علی',
      role: 'همسر',
      avatarPath: 'assets/images/father_avatar.png',
    ),
    UserModel(
      id: 'u3',
      name: 'سارا',
      role: 'فرزند',
      avatarPath: 'assets/images/child_avatar.png',
    ),
  ];

  // زمان پایه برای تست (امروز)
  static final DateTime _today = DateTime.now();

  // ۲. لیست رویدادهای تقویم (متصل به اعضای خانواده)
  static List<EventModel> get calendarEvents => [
    // رویدادهای مادر (u1)
    EventModel(
      id: 'e1',
      userId: 'u1',
      title: 'مصرف قرص ویتامین D',
      type: EventType.medicine,
      date: _today,
      time: '08:00',
      description: 'بعد از صبحانه',
    ),
    EventModel(
      id: 'e2',
      userId: 'u1',
      title: 'ویزیت دکتر زنان',
      type: EventType.doctor,
      date: _today.add(const Duration(days: 2)), // پس فردا
      time: '16:30',
      description: 'مطب دکتر احمدی',
    ),

    // رویدادهای همسر (u2)
    EventModel(
      id: 'e3',
      userId: 'u2',
      title: 'داروی فشار خون',
      type: EventType.medicine,
      date: _today,
      time: '09:00',
      description: 'یک عدد',
    ),

    // رویدادهای فرزند (u3)
    EventModel(
      id: 'e4',
      userId: 'u3',
      title: 'چکاپ ماهانه اطفال',
      type: EventType.checkup,
      date: _today.add(const Duration(days: 1)), // فردا
      time: '10:00',
      description: 'کلینیک کودکان',
    ),
     EventModel(
      id: 'e5',
      userId: 'u3',
      title: 'شربت سرماخوردگی',
      type: EventType.medicine,
      date: _today,
      time: '14:00',
      description: '۵ میلی‌لیتر',
    ),
  ];
}
