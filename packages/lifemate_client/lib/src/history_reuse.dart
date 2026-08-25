import 'recurrence.dart';

class CareEventReuseDraft {
  const CareEventReuseDraft({
    required this.eventType,
    required this.title,
    required this.timeZone,
    required this.patientReminderMinutesBefore,
    required this.caregiverReminderMinutesBefore,
    this.providerName,
    this.specialty,
    this.medicationName,
    this.doseText,
    this.administrationRoute,
    this.reason,
    this.instructions,
    this.centerName,
    this.addressLine,
    this.phoneNumber,
    this.recurrence = const RecurrenceRule.none(),
  });

  final String eventType;
  final String title;
  final String? providerName;
  final String? specialty;
  final String? medicationName;
  final String? doseText;
  final String? administrationRoute;
  final String? reason;
  final String? instructions;
  final String? centerName;
  final String? addressLine;
  final String? phoneNumber;
  final String timeZone;
  final RecurrenceRule recurrence;
  final int patientReminderMinutesBefore;
  final int caregiverReminderMinutesBefore;

  factory CareEventReuseDraft.fromHistory(Map<String, dynamic> source) {
    final eventType = source['eventType']?.toString().trim().toLowerCase();
    if (eventType != 'appointment' && eventType != 'injection') {
      throw const FormatException('Unsupported care event type for reuse.');
    }
    final title = source['title']?.toString().trim() ?? '';
    if (title.isEmpty) throw const FormatException('Care event title is required.');
    return CareEventReuseDraft(
      eventType: eventType!,
      title: title,
      providerName: _nullable(source['providerName']),
      specialty: _nullable(source['specialty']),
      medicationName: _nullable(source['medicationName']),
      doseText: _nullable(source['doseText']),
      administrationRoute: _nullable(source['administrationRoute']),
      reason: _nullable(source['reason']),
      instructions: _nullable(source['instructions']),
      centerName: _nullable(source['centerName']),
      addressLine: _nullable(source['addressLine']),
      phoneNumber: _nullable(source['phoneNumber']),
      timeZone: _nullable(source['timeZone']) ?? 'Asia/Tehran',
      recurrence: _freshRecurrence(source['recurrence']),
      patientReminderMinutesBefore:
          int.tryParse(source['patientReminderMinutesBefore']?.toString() ?? '') ?? 30,
      caregiverReminderMinutesBefore:
          int.tryParse(source['caregiverReminderMinutesBefore']?.toString() ?? '') ?? 60,
    );
  }
}

class TreatmentReuseDraft {
  const TreatmentReuseDraft({
    required this.medicationName,
    required this.form,
    required this.doseText,
    required this.timeZone,
    required this.schedules,
    required this.patientReminderMinutesBefore,
    required this.caregiverReminderMinutesBefore,
    this.strengthText,
    this.instructions,
  });

  final String medicationName;
  final String? strengthText;
  final String form;
  final String doseText;
  final String? instructions;
  final String timeZone;
  final List<Map<String, String>> schedules;
  final int patientReminderMinutesBefore;
  final int caregiverReminderMinutesBefore;

  factory TreatmentReuseDraft.fromHistory(Map<String, dynamic> source) {
    final medication = source['medication'];
    if (medication is! Map) {
      throw const FormatException('Treatment medication is required.');
    }
    final medicationName = medication['name']?.toString().trim() ?? '';
    if (medicationName.isEmpty) {
      throw const FormatException('Medication name is required.');
    }
    final schedules = <Map<String, String>>[];
    final rawSchedules = source['schedules'];
    if (rawSchedules is List) {
      for (final raw in rawSchedules) {
        if (raw is! Map) continue;
        final day = raw['dayOfWeek']?.toString().trim() ?? '';
        final time = raw['localTime']?.toString().trim() ?? '';
        if (day.isEmpty || time.isEmpty) continue;
        schedules.add({'dayOfWeek': day, 'localTime': time});
      }
    }
    return TreatmentReuseDraft(
      medicationName: medicationName,
      strengthText: _nullable(medication['strengthText']),
      form: _nullable(medication['form']) ?? 'other',
      doseText: source['doseText']?.toString().trim() ?? '',
      instructions: _nullable(source['instructions']),
      timeZone: _nullable(source['timeZone']) ?? 'Asia/Tehran',
      schedules: List.unmodifiable(schedules),
      patientReminderMinutesBefore:
          int.tryParse(source['patientReminderMinutesBefore']?.toString() ?? '') ?? 30,
      caregiverReminderMinutesBefore:
          int.tryParse(source['caregiverReminderMinutesBefore']?.toString() ?? '') ?? 60,
    );
  }
}

RecurrenceRule _freshRecurrence(dynamic raw) {
  final previous = RecurrenceRule.fromJson(raw);
  if (!previous.enabled) return const RecurrenceRule.none();
  return RecurrenceRule(
    enabled: true,
    unit: previous.unit,
    interval: previous.interval,
    weekdays: previous.weekdays,
    maxOccurrences: previous.maxOccurrences,
  );
}

String? _nullable(dynamic value) {
  final normalized = value?.toString().trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}
