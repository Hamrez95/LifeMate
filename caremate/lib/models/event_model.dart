enum EventType { medicine, appointment, injection, doctor, checkup, other }

class EventModel {
  final String id;
  final String userId;
  final String title;
  final String time;
  final String? description;
  final EventType type;
  final DateTime date;
  final int? repeatIntervalInDays;
  final DateTime? endDate;
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

  EventModel copyWith({required DateTime newDate, bool? newIsCompleted}) {
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
