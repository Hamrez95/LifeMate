import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  final medication = CareItem.fromTreatmentPlan({
    'id': 'med-1',
    'status': 'active',
    'doseText': '۱ عدد',
    'medication': {'name': 'ویتامین B'},
    'schedules': [
      {'localTime': '09:30'},
    ],
  });
  final visit = CareItem.fromCareEvent({
    'id': 'visit-1',
    'eventType': 'appointment',
    'title': 'چکاپ زنان',
    'providerName': 'دکتر سارا راد',
    'centerName': 'مرکز الوند',
    'specialty': 'زنان',
    'scheduledLocalDate': '2026-08-17',
    'scheduledLocalTime': '18:30',
    'status': 'scheduled',
  });
  final injection = CareItem.fromCareEvent({
    'id': 'inj-1',
    'eventType': 'injection',
    'title': 'B12',
    'doseText': '۱ عدد',
    'centerName': 'درمانگاه',
    'scheduledLocalDate': '2026-08-17',
    'scheduledLocalTime': '21:30',
    'status': 'scheduled',
  });

  test('unified list contains medication visit and injection', () {
    expect(
      {medication.type, visit.type, injection.type},
      {CareItemType.medication, CareItemType.visit, CareItemType.injection},
    );
  });

  test('filter by type keeps injection', () {
    final result = CareItem.filterAndSort([
      medication,
      visit,
      injection,
    ], type: CareItemType.injection);
    expect(result.map((item) => item.title), ['B12']);
  });

  test('search indexes doctor and clinic', () {
    expect(CareItem.filterAndSort([visit], query: 'سارا'), hasLength(1));
    expect(CareItem.filterAndSort([visit], query: 'الوند'), hasLength(1));
  });

  test('search indexes medication and injection title', () {
    expect(
      CareItem.filterAndSort([medication], query: 'ویتامین'),
      hasLength(1),
    );
    expect(CareItem.filterAndSort([injection], query: 'b12'), hasLength(1));
  });

  test('taken dose occurrence is a completed medication care item', () {
    final taken = CareItem.fromDoseOccurrence(
      {
        'id': 'dose-1',
        'treatmentPlanId': 'med-1',
        'scheduledLocalDate': '2026-08-08',
        'scheduledLocalTime': '09:30',
        'status': 'Taken',
      },
      {
        'id': 'med-1',
        'status': 'active',
        'doseText': '۱ عدد',
        'medication': {'name': 'ویتامین B'},
      },
    );

    expect(taken.type, CareItemType.medication);
    expect(taken.isCompleted, isTrue);
    expect(
      CareItem.filterAndSort([taken], status: CareItemStatusFilter.completed),
      hasLength(1),
    );
  });

  test('date range filter is inclusive and uses occurrence date', () {
    final inside = CareItem.fromCareEvent({
      'id': 'visit-range',
      'eventType': 'appointment',
      'title': 'ویزیت بازه',
      'scheduledLocalDate': '2026-08-17',
      'scheduledLocalTime': '10:00',
      'status': 'scheduled',
    });
    final outside = CareItem.fromCareEvent({
      'id': 'visit-outside',
      'eventType': 'appointment',
      'title': 'ویزیت خارج بازه',
      'scheduledLocalDate': '2026-08-20',
      'scheduledLocalTime': '10:00',
      'status': 'scheduled',
    });

    final result = CareItem.filterAndSort(
      [inside, outside],
      fromDate: DateTime(2026, 8, 17),
      toDate: DateTime(2026, 8, 17),
    );
    expect(result.map((item) => item.id), ['visit-range']);
  });
}
