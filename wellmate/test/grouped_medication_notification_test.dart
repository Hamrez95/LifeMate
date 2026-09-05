import 'package:flutter_test/flutter_test.dart';

import 'package:wellmate/models/schedule_item_model.dart';
import 'package:wellmate/providers/grouped_medication_notification.dart';

ScheduleItemModel medicine({
  required String id,
  required String title,
  required DateTime scheduledAtUtc,
  int reminderLead = 0,
}) =>
    ScheduleItemModel(
      id: id,
      title: title,
      time: '08:00',
      dosage: '10 mg',
      type: 'medicine',
      frequency: 'every 8 hours',
      scheduledAtUtc: scheduledAtUtc,
      patientReminderMinutesBefore: reminderLead,
      status: 'scheduled',
      version: 2,
    );

void main() {
  test('only equal trigger instants become a group', () {
    final at = DateTime.utc(2026, 9, 1, 8);
    final grouped = groupMedicationCandidates([
      GroupedMedicationCandidate(
        item: medicine(id: 'a', title: 'A', scheduledAtUtc: at),
        scheduledUtc: at,
        triggerUtc: at,
      ),
      GroupedMedicationCandidate(
        item: medicine(id: 'b', title: 'B', scheduledAtUtc: at),
        scheduledUtc: at,
        triggerUtc: at,
      ),
      GroupedMedicationCandidate(
        item: medicine(
          id: 'c',
          title: 'C',
          scheduledAtUtc: at.add(const Duration(minutes: 10)),
        ),
        scheduledUtc: at.add(const Duration(minutes: 10)),
        triggerUtc: at.add(const Duration(minutes: 10)),
      ),
    ]);

    expect(grouped, hasLength(1));
    expect(grouped[at], hasLength(2));
    expect(grouped[at]!.map((value) => value.item.id), ['a', 'b']);
  });

  test('different reminder leads do not collapse different trigger instants', () {
    final scheduled = DateTime.utc(2026, 9, 1, 8);
    final grouped = groupMedicationCandidates([
      GroupedMedicationCandidate(
        item: medicine(
          id: 'a',
          title: 'A',
          scheduledAtUtc: scheduled,
          reminderLead: 0,
        ),
        scheduledUtc: scheduled,
        triggerUtc: scheduled,
      ),
      GroupedMedicationCandidate(
        item: medicine(
          id: 'b',
          title: 'B',
          scheduledAtUtc: scheduled,
          reminderLead: 15,
        ),
        scheduledUtc: scheduled,
        triggerUtc: scheduled.subtract(const Duration(minutes: 15)),
      ),
    ]);

    expect(grouped, isEmpty);
  });

  test('affected scope follows old and new grouped reminder dependencies', () {
    final affected = expandAffectedMedicationOccurrenceIds(
      affectedOccurrenceIds: const ['dose-a'],
      groupMemberships: const [
        ['dose-a', 'dose-b'],
        ['dose-b', 'dose-c'],
        ['unrelated-a', 'unrelated-b'],
      ],
    );

    expect(affected, {'dose-a', 'dose-b', 'dose-c'});
    expect(affected.contains('unrelated-a'), isFalse);
  });

  test('empty affected scope never expands grouped reminders', () {
    expect(
      expandAffectedMedicationOccurrenceIds(
        affectedOccurrenceIds: const [' ', ''],
        groupMemberships: const [
          ['dose-a', 'dose-b'],
        ],
      ),
      isEmpty,
    );
  });

  test('group payload keeps every occurrence/version independently addressable', () {
    const target = GroupedMedicationNotificationTarget(
      groupKey: 'group-1',
      isPersian: false,
      doses: [
        GroupedMedicationDoseTarget(
          occurrenceId: 'occ-a',
          version: 2,
          clientRequestId: 'request-a',
          title: 'Medicine A',
        ),
        GroupedMedicationDoseTarget(
          occurrenceId: 'occ-b',
          version: 5,
          clientRequestId: 'request-b',
          title: 'Medicine B',
        ),
      ],
    );

    final decoded = decodeGroupedMedicationPayload(
      encodeGroupedMedicationPayload(target),
    );
    expect(decoded, isNotNull);
    expect(decoded!.doses.map((dose) => dose.occurrenceId), ['occ-a', 'occ-b']);
    expect(decoded.doses.map((dose) => dose.version), [2, 5]);
  });

  test('lock-screen copy is bounded and does not include dosage text', () {
    const doses = [
      GroupedMedicationDoseTarget(
        occurrenceId: '1',
        version: 1,
        clientRequestId: 'r1',
        title: 'A',
      ),
      GroupedMedicationDoseTarget(
        occurrenceId: '2',
        version: 1,
        clientRequestId: 'r2',
        title: 'B',
      ),
      GroupedMedicationDoseTarget(
        occurrenceId: '3',
        version: 1,
        clientRequestId: 'r3',
        title: 'C',
      ),
      GroupedMedicationDoseTarget(
        occurrenceId: '4',
        version: 1,
        clientRequestId: 'r4',
        title: 'D',
      ),
    ];
    final body = groupedMedicationBody(doses, false);
    expect(body, 'A, B, C and 1 more');
    expect(body.contains('mg'), isFalse);
  });
}
