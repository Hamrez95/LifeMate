import 'package:caremate/models/care_daily_summary.dart';
import 'package:caremate/models/care_home_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no treatment plan produces no synthetic daily summary', () {
    final snapshot = CareHomeSnapshot(
      currentUser: const <String, dynamic>{},
      relationships: const <CareHomeRelationship>[
        CareHomeRelationship(
          relationshipId: 'rel-a',
          patientUserId: 'a',
          patientDisplayName: 'Mom',
          canViewWomenCalendar: false,
        ),
      ],
      queueItems: const <CareHomeTreatmentItem>[],
      todayItems: const <CareHomeTreatmentItem>[],
      companion: CareCompanionHomeSummary.locked(),
    );

    expect(CareDailySummary.fromSnapshot(snapshot), isEmpty);
  });
}
