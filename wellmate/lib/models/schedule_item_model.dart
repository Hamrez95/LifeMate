class ScheduleItemModel {
  final String id;
  final String title;
  final String time;
  final String dosage;
  final String type;
  final String frequency;
  final bool isDone;
  final DateTime? startDate;
  final int? intervalDays;

  ScheduleItemModel({
    required this.id,
    required this.title,
    required this.time,
    required this.dosage,
    required this.type,
    this.isDone = false,
    this.startDate,
    this.intervalDays,
    required this.frequency,
  });

  factory ScheduleItemModel.fromJson(Map<String, dynamic> json) {
    return ScheduleItemModel(
      id: json['id']?.toString() ?? '',
      // پشتیبانی از هر دو کلید title و name
      title: json['title'] ?? json['name'] ?? '',
      time: json['time'] ?? '',
      // پشتیبانی از هر دو کلید dosage و details
      dosage: json['dosage'] ?? json['details'] ?? '',
      type: json['type'] ?? 'default', // اینجا type درست خوانده می‌شود
      isDone: json['is_done'] ?? false,
      frequency: json['frequency'] ?? 'روزانه',
      startDate:
          json['startDate'] != null ? DateTime.parse(json['startDate']) : null,
      intervalDays: json['intervalDays'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'time': time,
      'dosage': dosage,
      'type': type,
      'is_done': isDone,
      'frequency': frequency,
      'startDate': startDate?.toIso8601String(),
      'intervalDays': intervalDays,
    };
  }

  ScheduleItemModel copyWith({
    String? id,
    String? title,
    String? time,
    String? dosage,
    String? type,
    bool? isDone,
    String? frequency,
    DateTime? startDate,
    int? intervalDays,
  }) {
    return ScheduleItemModel(
      id: id ?? this.id,
      title: title ?? this.title,
      time: time ?? this.time,
      dosage: dosage ?? this.dosage,
      type: type ?? this.type,
      isDone: isDone ?? this.isDone,
      frequency: frequency ?? this.frequency,
      startDate: startDate ?? this.startDate,
      intervalDays: intervalDays ?? this.intervalDays,
    );
  }
}
