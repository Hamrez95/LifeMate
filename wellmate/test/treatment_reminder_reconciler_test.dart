import 'package:flutter_test/flutter_test.dart';
import 'package:wellmate/models/schedule_item_model.dart';
import 'package:wellmate/providers/treatment_reminder_reconciler.dart';

void main() {
  test('authoritative treatment refresh replaces only future medicine reminders', () {
    final now = DateTime.utc(2026, 9, 5, 8);
    final current = <ScheduleItemModel>[
      ScheduleItemModel(
        id: 'old-dose',
        title: 'Old medicine',
        time: '09:00',
        dosage: '1',
        type: 'medicine',
        frequency: 'daily',
        scheduledAtUtc: now.add(const Duration(hours: 1)),
      ),
      ScheduleItemModel(
        id: 'appointment-1',
        title: 'Doctor',
        time: '10:00',
        dosage: '',
        type: 'appointment',
        frequency: 'appointment',
        scheduledAtUtc: now.add(const Duration(hours: 2)),
      ),
    ];

    final next = reconcileTreatmentReminderWindow(
      currentItems: current,
      now: now,
      serverSnapshot: {
        'treatmentPlans': [
          {
            'id': 'plan-1',
            'doseText': '5 mg',
            'medication': {'name': 'Fresh medicine'},
          },
        ],
        'doseOccurrences': [
          {
            'id': 'fresh-dose',
            'treatmentPlanId': 'plan-1',
            'status': 'scheduled',
            'version': 4,
            'scheduledAtUtc': now.add(const Duration(hours: 3)).toIso8601String(),
            'scheduledLocalDate': '2026-09-05',
            'scheduledLocalTime': '11:00:00',
            'patientReminderMinutesBefore': 20,
            'caregiverReminderMinutesBefore': 45,
          },
          {
            'id': 'taken-dose',
            'treatmentPlanId': 'plan-1',
            'status': 'taken',
            'scheduledAtUtc': now.add(const Duration(hours: 4)).toIso8601String(),
            'scheduledLocalDate': '2026-09-05',
            'scheduledLocalTime': '12:00:00',
          },
          {
            'id': 'past-dose',
            'treatmentPlanId': 'plan-1',
            'status': 'scheduled',
            'scheduledAtUtc': now.subtract(const Duration(minutes: 1)).toIso8601String(),
            'scheduledLocalDate': '2026-09-05',
            'scheduledLocalTime': '07:59:00',
          },
        ],
      },
    );

    expect(next.map((item) => item.id), ['appointment-1', 'fresh-dose']);
    final medicine = next.last;
    expect(medicine.title, 'Fresh medicine');
    expect(medicine.dosage, '5 mg');
    expect(medicine.version, 4);
    expect(medicine.patientReminderMinutesBefore, 20);
    expect(medicine.caregiverReminderMinutesBefore, 45);
  });

  test('pending sync dose is never regenerated as a reminder', () {
    final now = DateTime.utc(2026, 9, 5, 8);
    final next = reconcileTreatmentReminderWindow(
      currentItems: const <ScheduleItemModel>[],
      now: now,
      serverSnapshot: {
        'treatmentPlans': [
          {'id': 'plan-1', 'doseText': '1 tablet'},
        ],
        'doseOccurrences': [
          {
            'id': 'pending-dose',
            'treatmentPlanId': 'plan-1',
            'status': 'pending_sync',
            'pendingSync': true,
            'scheduledAtUtc': now.add(const Duration(hours: 1)).toIso8601String(),
          },
        ],
      },
    );

    expect(next, isEmpty);
  });

  test('unchanged medicine projection produces no affected occurrence IDs', () {
    final scheduledAt = DateTime.utc(2026, 9, 5, 9);
    final current = <ScheduleItemModel>[
      ScheduleItemModel(
        id: 'dose-1',
        title: 'Medication',
        time: '12:30',
        dosage: '1 tablet',
        type: 'medicine',
        frequency: 'According to the treatment plan',
        status: 'scheduled',
        version: 3,
        scheduledAtUtc: scheduledAt,
        patientReminderMinutesBefore: 15,
        caregiverReminderMinutesBefore: 30,
      ),
    ];
    final next = <ScheduleItemModel>[
      ScheduleItemModel(
        id: 'dose-1',
        title: 'Medication',
        time: '12:30',
        dosage: '1 tablet',
        type: 'medicine',
        frequency: 'According to the treatment plan',
        status: 'scheduled',
        version: 3,
        scheduledAtUtc: scheduledAt,
        patientReminderMinutesBefore: 15,
        caregiverReminderMinutesBefore: 30,
      ),
    ];

    expect(
      changedTreatmentReminderOccurrenceIds(
        currentItems: current,
        nextItems: next,
      ),
      isEmpty,
    );
  });

  test('added removed and revised medicine occurrences are affected', () {
    final now = DateTime.utc(2026, 9, 5, 8);
    final current = <ScheduleItemModel>[
      ScheduleItemModel(
        id: 'removed-dose',
        title: 'Medication A',
        time: '09:00',
        dosage: '1',
        type: 'medicine',
        frequency: 'daily',
        version: 1,
        scheduledAtUtc: now.add(const Duration(hours: 1)),
      ),
      ScheduleItemModel(
        id: 'revised-dose',
        title: 'Medication B',
        time: '10:00',
        dosage: '1',
        type: 'medicine',
        frequency: 'daily',
        version: 1,
        scheduledAtUtc: now.add(const Duration(hours: 2)),
      ),
      ScheduleItemModel(
        id: 'appointment-1',
        title: 'Doctor',
        time: '11:00',
        dosage: '',
        type: 'appointment',
        frequency: 'appointment',
        version: 1,
        scheduledAtUtc: now.add(const Duration(hours: 3)),
      ),
    ];
    final next = <ScheduleItemModel>[
      ScheduleItemModel(
        id: 'revised-dose',
        title: 'Medication B',
        time: '10:30',
        dosage: '1',
        type: 'medicine',
        frequency: 'daily',
        version: 2,
        scheduledAtUtc: now.add(const Duration(hours: 2, minutes: 30)),
      ),
      ScheduleItemModel(
        id: 'new-dose',
        title: 'Medication C',
        time: '12:00',
        dosage: '1',
        type: 'medicine',
        frequency: 'daily',
        version: 1,
        scheduledAtUtc: now.add(const Duration(hours: 4)),
      ),
      current.last,
    ];

    expect(
      changedTreatmentReminderOccurrenceIds(
        currentItems: current,
        nextItems: next,
      ),
      {'removed-dose', 'revised-dose', 'new-dose'},
    );
  });

  test('incomplete authoritative snapshot fails closed', () {
    expect(
      () => reconcileTreatmentReminderWindow(
        currentItems: const <ScheduleItemModel>[],
        serverSnapshot: const {'treatmentPlans': <Object>[]},
        now: DateTime.utc(2026, 9, 5),
      ),
      throwsStateError,
    );
  });
}
