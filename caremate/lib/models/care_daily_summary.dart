import 'care_home_snapshot.dart';

class CareDailySummary {
  const CareDailySummary({
    required this.patientUserId,
    required this.patientDisplayName,
    required this.total,
    required this.completed,
    required this.pending,
    required this.alerts,
  });

  final String patientUserId;
  final String patientDisplayName;
  final int total;
  final int completed;
  final int pending;
  final int alerts;

  int get unresolved => pending + alerts;

  static List<CareDailySummary> fromSnapshot(CareHomeSnapshot snapshot) {
    final summaries = <CareDailySummary>[];
    for (final relationship in snapshot.relationships) {
      final items = snapshot.todayItems
          .where((item) => item.patientUserId == relationship.patientUserId)
          .toList(growable: false);
      if (items.isEmpty) continue;
      summaries.add(
        CareDailySummary(
          patientUserId: relationship.patientUserId,
          patientDisplayName: relationship.patientDisplayName,
          total: items.length,
          completed: items.where((item) => item.isCompleted).length,
          pending: items.where((item) => item.isQueueEligible).length,
          alerts: items.where((item) => item.isAlert).length,
        ),
      );
    }
    return List<CareDailySummary>.unmodifiable(summaries);
  }
}
