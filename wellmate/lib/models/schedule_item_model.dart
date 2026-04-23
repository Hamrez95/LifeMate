class ScheduleItemModel {
  final String id;
  final String title; // نام دارو یا فعالیت (مثلاً "ویتامین C")
  final String time; // زمان مصرف (مثلاً "08:00")
  final String dosage; // مقدار مصرف (مثلاً "۱ قرص")
  final String type; // نوع (برای نمایش آیکون مناسب، مثلاً "pill" یا "syrup")
  final bool isDone; // وضعیت انجام شدن یا نشدن

  ScheduleItemModel({
    required this.id,
    required this.title,
    required this.time,
    required this.dosage,
    required this.type,
    this.isDone = false,
  });

  // تبدیل JSON دریافتی از سرور به مدل دارت
  factory ScheduleItemModel.fromJson(Map<String, dynamic> json) {
    return ScheduleItemModel(
      id: json['id']?.toString() ?? '',
      title: json['title'] ?? '',
      time: json['time'] ?? '',
      dosage: json['dosage'] ?? '',
      type: json['type'] ?? 'default',
      isDone: json['is_done'] ?? false,
    );
  }

  // تبدیل مدل دارت به JSON برای ارسال به سرور
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'time': time,
      'dosage': dosage,
      'type': type,
      'is_done': isDone,
    };
  }

  // متدی برای کپی کردن آبجکت با مقادیر جدید (مثلاً وقتی کاربر تیک انجام را می‌زند)
  ScheduleItemModel copyWith({
    String? id,
    String? title,
    String? time,
    String? dosage,
    String? type,
    bool? isDone,
  }) {
    return ScheduleItemModel(
      id: id ?? this.id,
      title: title ?? this.title,
      time: time ?? this.time,
      dosage: dosage ?? this.dosage,
      type: type ?? this.type,
      isDone: isDone ?? this.isDone,
    );
  }
}
