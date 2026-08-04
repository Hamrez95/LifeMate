class ScheduleItemModel {
  final String id;
  final String title;
  final String time;
  final String dosage;
  final String type;
  final String frequency;
  final bool isDone;
  final String status;
  final int version;
  final DateTime? scheduledAtUtc;
  final DateTime? startDate;
  final int? intervalDays;
  final int patientReminderMinutesBefore;
  final int caregiverReminderMinutesBefore;

  ScheduleItemModel({
    required this.id,
    required this.title,
    required this.time,
    required this.dosage,
    required this.type,
    this.isDone = false,
    this.status = 'scheduled',
    this.version = 1,
    this.scheduledAtUtc,
    this.startDate,
    this.intervalDays,
    this.patientReminderMinutesBefore = 30,
    this.caregiverReminderMinutesBefore = 60,
    required this.frequency,
  });

  factory ScheduleItemModel.fromJson(Map<String, dynamic> json) {
    final status = (json['status'] ?? 'scheduled').toString();
    return ScheduleItemModel(
      id: json['id']?.toString() ?? '',
      title: json['title'] ?? json['name'] ?? '',
      time: json['time'] ?? '',
      dosage: json['dosage'] ?? json['details'] ?? '',
      type: json['type'] ?? 'default',
      isDone: json['is_done'] ?? status == 'taken' || status == 'skipped',
      status: status,
      version: json['version'] is int ? json['version'] as int : 1,
      scheduledAtUtc: json['scheduledAtUtc'] == null
          ? null
          : DateTime.tryParse(json['scheduledAtUtc'].toString())?.toUtc(),
      frequency: json['frequency'] ?? 'روزانه',
      startDate: json['startDate'] != null
          ? DateTime.parse(json['startDate'])
          : null,
      intervalDays: json['intervalDays'],
      patientReminderMinutesBefore:
          int.tryParse(
            json['patientReminderMinutesBefore']?.toString() ?? '',
          ) ??
          30,
      caregiverReminderMinutesBefore:
          int.tryParse(
            json['caregiverReminderMinutesBefore']?.toString() ?? '',
          ) ??
          60,
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
      'status': status,
      'version': version,
      'scheduledAtUtc': scheduledAtUtc?.toIso8601String(),
      'frequency': frequency,
      'startDate': startDate?.toIso8601String(),
      'intervalDays': intervalDays,
      'patientReminderMinutesBefore': patientReminderMinutesBefore,
      'caregiverReminderMinutesBefore': caregiverReminderMinutesBefore,
    };
  }

  ScheduleItemModel copyWith({
    String? id,
    String? title,
    String? time,
    String? dosage,
    String? type,
    bool? isDone,
    String? status,
    int? version,
    DateTime? scheduledAtUtc,
    String? frequency,
    DateTime? startDate,
    int? intervalDays,
    int? patientReminderMinutesBefore,
    int? caregiverReminderMinutesBefore,
  }) {
    return ScheduleItemModel(
      id: id ?? this.id,
      title: title ?? this.title,
      time: time ?? this.time,
      dosage: dosage ?? this.dosage,
      type: type ?? this.type,
      isDone: isDone ?? this.isDone,
      status: status ?? this.status,
      version: version ?? this.version,
      scheduledAtUtc: scheduledAtUtc ?? this.scheduledAtUtc,
      frequency: frequency ?? this.frequency,
      startDate: startDate ?? this.startDate,
      intervalDays: intervalDays ?? this.intervalDays,
      patientReminderMinutesBefore:
          patientReminderMinutesBefore ?? this.patientReminderMinutesBefore,
      caregiverReminderMinutesBefore:
          caregiverReminderMinutesBefore ?? this.caregiverReminderMinutesBefore,
    );
  }
}
