import 'package:flutter_test/flutter_test.dart';
import 'package:wellmate/core/widgets/medication_home_widget_service.dart';

void main() {
  group('Medication home widget data', () {
    test('converts all western digits to Persian digits', () {
      expect(
        toPersianDigits('Metformin 500 - 12:30 - 1'),
        'Metformin ۵۰۰ - ۱۲:۳۰ - ۱',
      );
    });

    test('selects the nearest future medicine and maps visible fields', () {
      final now = DateTime(2026, 8, 11, 9);
      final result = selectMedicationWidgetData(
        now: now,
        treatmentPlans: [
          {
            'id': 'plan-late',
            'doseText': '2 capsule',
            'instructions': 'بعد از ناهار',
            'medication': {
              'name': 'آموکسی‌سیلین',
              'strengthText': '250 میلی‌گرم',
            },
          },
          {
            'id': 'plan-next',
            'doseText': '1 عدد',
            'instructions': 'برای قلب و چربی خون',
            'medication': {
              'name': 'آتورواستاتین',
              'strengthText': '20 میلی‌گرم',
            },
          },
        ],
        doseOccurrences: [
          {
            'id': 'dose-late',
            'treatmentPlanId': 'plan-late',
            'status': 'scheduled',
            'version': 3,
            'scheduledLocalDate': '2026-08-11',
            'scheduledLocalTime': '14:00:00',
          },
          {
            'id': 'dose-next',
            'treatmentPlanId': 'plan-next',
            'status': 'scheduled',
            'version': 4,
            'scheduledLocalDate': '2026-08-11',
            'scheduledLocalTime': '11:00:00',
          },
        ],
      );

      expect(result, isNotNull);
      expect(result!.occurrenceId, 'dose-next');
      expect(result.version, 4);
      expect(result.treatmentName, 'آتورواستاتین');
      expect(result.description, 'برای قلب و چربی خون');
      expect(result.dose, '۲۰ میلی‌گرم');
      expect(result.quantity, '۱ عدد');
      expect(result.time, '۱۱:۰۰');
      expect(result.scheduledAt, DateTime(2026, 8, 11, 11));
    });

    test('keeps the newest overdue scheduled dose actionable', () {
      final now = DateTime(2026, 8, 11, 18);
      final result = selectMedicationWidgetData(
        now: now,
        treatmentPlans: [
          {
            'id': 'plan',
            'doseText': '1 عدد',
            'medication': {
              'name': 'متفورمین',
              'strengthText': '500 میلی‌گرم',
              'notes': 'بعد از غذا',
            },
          },
        ],
        doseOccurrences: [
          {
            'id': 'older',
            'treatmentPlanId': 'plan',
            'status': 'missed',
            'scheduledLocalDate': '2026-08-11',
            'scheduledLocalTime': '08:00:00',
          },
          {
            'id': 'latest',
            'treatmentPlanId': 'plan',
            'status': 'scheduled',
            'scheduledLocalDate': '2026-08-11',
            'scheduledLocalTime': '17:30:00',
          },
        ],
      );

      expect(result, isNotNull);
      expect(result!.occurrenceId, 'latest');
      expect(result.treatmentName, 'متفورمین');
      expect(result.description, 'بعد از غذا');
      expect(result.dose, '۵۰۰ میلی‌گرم');
      expect(result.quantity, '۱ عدد');
      expect(result.time, '۱۷:۳۰');
    });
  });
}
