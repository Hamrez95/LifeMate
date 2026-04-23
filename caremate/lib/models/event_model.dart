// lib/models/event_model.dart

enum EventType { medicine, doctor, checkup, other }

class EventModel {
  final String id;
  final String userId;
  final String title;
  final String time;
  final String? description;
  final EventType type;


  // برای رویدادهای تکرارشونده، این تاریخ شروع دوره است.
  // برای رویدادهای تکی، این همان تاریخ رویداد است.
  final DateTime date; 
  
  // برای رویدادهای تکرارشونده: فاصله تکرار به روز (مثلا ۱ برای هر روز، ۷ برای هفتگی)
  final int? repeatIntervalInDays;

  // برای رویدaدهای تکرارشونده: تاریخ پایان دوره (اگر null باشد یعنی برای همیشه تکرار می‌شود)
  final DateTime? endDate;

  // وضعیت انجام رویداد برای یک تاریخ خاص
  // مثال: { '2024-05-20': true, '2024-05-21': false }
  // برای رویدادهای تکی، فقط یک ورودی خواهد داشت.
  final bool? isCompleted;

  EventModel({
    required this.id,
    required this.userId,
    required this.title,
    required this.date,
    required this.time,
    this.description,
    this.type = EventType.other,
    this.isCompleted,
    this.repeatIntervalInDays,
    this.endDate,
  });

  // یک متد کمکی برای کپی کردن یک رویداد با تاریخی متفاوت (برای تولید رویدادهای تکراری لازم است)
  EventModel copyWith({
    required DateTime newDate,
    bool? newIsCompleted,
  }) {
    return EventModel(
      id: id,
      userId: userId,
      title: title,
      date: newDate,
      time: time,
      description: description,
      type: type,
      isCompleted: newIsCompleted,
      repeatIntervalInDays: repeatIntervalInDays,
      endDate: endDate,
    );
  }
}
