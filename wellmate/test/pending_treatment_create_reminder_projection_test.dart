import 'package:flutter_test/flutter_test.dart';
import 'package:wellmate/providers/pending_treatment_create_reminder_projection.dart';

Map<String, dynamic> pendingCreate({
  String requestId = 'request-sensitive-123',
  String startDate = '2026-09-07',
  String? endDate = '2026-09-07',
  String timeZone = 'Asia/Tehran',
  int leadMinutes = 30,
  bool pendingSync = true,
  bool recurrenceEnabled = false,
  List<Map<String, dynamic>>? schedules,
}) => <String, dynamic>{
  'pendingSync': pendingSync,
  'clientRequestId': requestId,
  'startDate': startDate,
  if (endDate != null) 'endDate': endDate,
  'timeZone': timeZone,
  'patientReminderMinutesBefore': leadMinutes,
  'recurrence': <String, dynamic>{'enabled': recurrenceEnabled},
  'schedules': schedules ??
      <Map<String, dynamic>>[
        <String, dynamic>{'dayOfWeek': 'monday', 'localTime': '09:00'},
      ],
};

void main() {
  final nowUtc = DateTime.utc(2026, 9, 7, 4);

  test('projects pending local schedule using the declared timezone and lead', () {
    final reminders = projectPendingTreatmentCreateReminders(
      pendingCreates: <Map<String, dynamic>>[pendingCreate()],
      nowUtc: nowUtc,
    );

    expect(reminders, hasLength(1));
    expect(reminders.single.triggerUtc, DateTime.utc(2026, 9, 7, 5));
    expect(
      reminders.single.sourceOccurrenceKey,
      startsWith('wellmate:pending-treatment-create:'),
    );
  });

  test('keeps pending reminder identity opaque and deterministic', () {
    final first = projectPendingTreatmentCreateReminders(
      pendingCreates: <Map<String, dynamic>>[pendingCreate()],
      nowUtc: nowUtc,
    ).single;
    final second = projectPendingTreatmentCreateReminders(
      pendingCreates: <Map<String, dynamic>>[pendingCreate()],
      nowUtc: nowUtc,
    ).single;

    expect(first.sourceOccurrenceKey, second.sourceOccurrenceKey);
    expect(first.sourceRevision, second.sourceRevision);
    expect(first.sourceOccurrenceKey, isNot(contains('request-sensitive-123')));
  });

  test('deduplicates identical local schedules before reminder reconciliation', () {
    final reminders = projectPendingTreatmentCreateReminders(
      pendingCreates: <Map<String, dynamic>>[
        pendingCreate(
          schedules: <Map<String, dynamic>>[
            <String, dynamic>{'dayOfWeek': 'monday', 'localTime': '09:00'},
            <String, dynamic>{'dayOfWeek': 'monday', 'localTime': '09:00'},
          ],
        ),
      ],
      nowUtc: nowUtc,
    );

    expect(reminders, hasLength(1));
  });

  test('fails closed for unsafe pending-create shapes', () {
    final unsafe = <Map<String, dynamic>>[
      pendingCreate(pendingSync: false),
      pendingCreate(recurrenceEnabled: true),
      pendingCreate(timeZone: 'Not/AZone'),
      pendingCreate(leadMinutes: -1),
      pendingCreate(leadMinutes: 10081),
      pendingCreate(startDate: '07-09-2026'),
      pendingCreate(
        schedules: <Map<String, dynamic>>[
          <String, dynamic>{'dayOfWeek': 'monday', 'localTime': '25:00'},
        ],
      ),
    ];

    for (final value in unsafe) {
      expect(
        projectPendingTreatmentCreateReminders(
          pendingCreates: <Map<String, dynamic>>[value],
          nowUtc: nowUtc,
        ),
        isEmpty,
      );
    }
  });

  test('revision changes when reminder semantics change but occurrence key does not', () {
    final baseline = projectPendingTreatmentCreateReminders(
      pendingCreates: <Map<String, dynamic>>[pendingCreate()],
      nowUtc: nowUtc,
    ).single;
    final changedLead = projectPendingTreatmentCreateReminders(
      pendingCreates: <Map<String, dynamic>>[pendingCreate(leadMinutes: 15)],
      nowUtc: nowUtc,
    ).single;

    expect(changedLead.sourceOccurrenceKey, baseline.sourceOccurrenceKey);
    expect(changedLead.sourceRevision, isNot(baseline.sourceRevision));
    expect(changedLead.triggerUtc, DateTime.utc(2026, 9, 7, 5, 15));
  });

  test('does not emit reminders outside the bounded horizon or in the past', () {
    final future = pendingCreate(
      startDate: '2026-11-02',
      endDate: '2026-11-02',
      schedules: <Map<String, dynamic>>[
        <String, dynamic>{'dayOfWeek': 'monday', 'localTime': '09:00'},
      ],
    );
    final alreadyTriggered = pendingCreate(leadMinutes: 120);

    expect(
      projectPendingTreatmentCreateReminders(
        pendingCreates: <Map<String, dynamic>>[future],
        nowUtc: nowUtc,
      ),
      isEmpty,
    );
    expect(
      projectPendingTreatmentCreateReminders(
        pendingCreates: <Map<String, dynamic>>[alreadyTriggered],
        nowUtc: DateTime.utc(2026, 9, 7, 4, 30),
      ),
      isEmpty,
    );
  });

  test('rejects non-positive horizons instead of silently broadening scope', () {
    expect(
      () => projectPendingTreatmentCreateReminders(
        pendingCreates: const <Map<String, dynamic>>[],
        nowUtc: nowUtc,
        horizon: Duration.zero,
      ),
      throwsArgumentError,
    );
  });
}
