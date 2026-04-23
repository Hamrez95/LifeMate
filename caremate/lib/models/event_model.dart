enum EventType { medicine, doctor, checkup, other }

class EventModel {
  final String id;
  final String userId;
  final String title;
  final EventType type;
  final DateTime date;
  final String time; 
  final String? description; 

  EventModel({
    required this.id,
    required this.userId,
    required this.title,
    required this.type,
    required this.date,
    required this.time,
    this.description,
  });
}
