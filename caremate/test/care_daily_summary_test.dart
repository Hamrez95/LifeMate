import 'package:caremate/models/care_daily_summary.dart';
import 'package:caremate/models/care_home_snapshot.dart';
import 'package:caremate/providers/care_notification_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  CareHomeTreatmentItem item({
    required String patient,
    required String name,
    required String id,
    required String status,
  }) {
    return CareHomeTreatmentItem(
      relationshipId: 'rel-$patient',
      patientUserId: patient,
      patientDisplayName: name,
      type: CareItemType.medication,
      treatmentId: 'plan-$id',
      occurrenceId: id,
      title: 'Medication',
      subtitle: '',
      scheduledAt: DateTime(2026, 8, 25, 9),
      scheduledLocalTime: '09:00',
      status: status,
      raw: const <String, dynamic>{},
    );
  }

  test('daily summaries stay person-scoped and use authoritative statuses', () {
    const relationships = <CareHomeRelationship>[
      CareHomeRelationship(
        relationshipId: 'rel-a',
        patientUserId: 'a',
        patientDisplayName: 'Mom',
        canViewWomenCalendar: false,
      ),
      CareHomeRelationship(
        relationshipId: 'rel-b',
        patientUserId: 'b',
        patientDisplayName: 'Dad',
        canViewWomenCalendar: false,
      ),
    ];
    final today = <CareHomeTreatmentItem>[
      item(patient: 'a', name: 'Mom', id: 'a1', status: 'taken'),
      item(patient: 'a', name: 'Mom', id: 'a2', status: 'missed'),
      item(patient: 'a', name: 'Mom', id: 'a3', status: 'scheduled'),
      item(patient: 'b', name: 'Dad', id: 'b1', status: 'completed'),
    ];
    final snapshot = CareHomeSnapshot(
      currentUser: const <String, dynamic>{},
      relationships: relationships,
      queueItems: const <CareHomeTreatmentItem>[],
      todayItems: today,
      companion: CareCompanionHomeSummary.locked(),
    );

    final summaries = CareDailySummary.fromSnapshot(snapshot);

    expect(summaries, hasLength(2));
    final mom = summaries.firstWhere((value) => value.patientUserId == 'a');
    expect(mom.total, 3);
    expect(mom.completed, 1);
    expect(mom.alerts, 1);
    expect(mom.pending, 1);
    final dad = summaries.firstWhere((value) => value.patientUserId == 'b');
    expect(dad.total, 1);
    expect(dad.completed, 1);
    expect(dad.unresolved, 0);
  });

  test('summary copy never turns incomplete data into a medical reassurance', () {
    const summary = CareDailySummary(
      patientUserId: 'a',
      patientDisplayName: 'Mom',
      total: 4,
      completed: 3,
      pending: 0,
      alerts: 1,
    );

    final copy = CareNotificationProvider.dailySummaryCopy(
      summary,
      isPersian: false,
    );

    expect(copy.title, contains('Mom'));
    expect(copy.body, contains('3 of 4'));
    expect(copy.body, contains('missed/skipped'));
    expect(copy.body.toLowerCase(), isNot(contains('everything is fine')));
  });

  test('all-done copy is limited to recorded treatment facts', () {
    const summary = CareDailySummary(
      patientUserId: 'a',
      patientDisplayName: 'Mom',
      total: 2,
      completed: 2,
      pending: 0,
      alerts: 0,
    );

    final copy = CareNotificationProvider.dailySummaryCopy(
      summary,
      isPersian: false,
    );

    expect(copy.body, contains('No recorded treatment item remains unresolved'));
  });

  test('preferred local time boundary is deterministic', () {
    expect(
      CareNotificationProvider.isDailySummaryDue(
        DateTime(2026, 8, 25, 19, 59),
        '20:00',
      ),
      isFalse,
    );
    expect(
      CareNotificationProvider.isDailySummaryDue(
        DateTime(2026, 8, 25, 20),
        '20:00:00',
      ),
      isTrue,
    );
    expect(
      CareNotificationProvider.isDailySummaryDue(
        DateTime(2026, 8, 25, 22),
        'invalid',
      ),
      isFalse,
    );
  });
}
