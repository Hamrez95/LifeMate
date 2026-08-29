import 'package:caremate/models/care_daily_summary.dart';
import 'package:caremate/providers/care_notification_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('partner and parent-care completion copy use different presentation', () {
    final item = <String, dynamic>{
      'patientDisplayName': 'Mum',
      'medicationName': 'Metformin',
      'evidenceClass': 'self_reported',
    };

    final partner = CareNotificationProvider.completionCopy(
      item,
      isPersian: false,
      relationshipType: 'partner',
    );
    final parentCare = CareNotificationProvider.completionCopy(
      item,
      isPersian: false,
      relationshipType: 'child_caring_for_parent',
    );

    expect(partner.title, '💚 A reassuring update from Mum');
    expect(parentCare.title, '💚 Mum care update');
    expect(partner.body, parentCare.body);
  });

  test('daily summary title changes by relationship but facts do not', () {
    const summary = CareDailySummary(
      patientUserId: 'patient-a',
      patientDisplayName: 'Mum',
      total: 3,
      completed: 2,
      pending: 1,
      alerts: 0,
    );

    final partner = CareNotificationProvider.dailySummaryCopy(
      summary,
      isPersian: false,
      relationshipType: 'partner',
    );
    final parentCare = CareNotificationProvider.dailySummaryCopy(
      summary,
      isPersian: false,
      relationshipType: 'child_caring_for_parent',
    );

    expect(partner.title, '☀️ Today with Mum');
    expect(parentCare.title, '☀️ Today’s care for Mum');
    expect(partner.body, parentCare.body);
    expect(parentCare.body, contains('2 of 3'));
  });

  test('relationship type never overrides disabled notification preference', () {
    final relationships = <Map<String, dynamic>>[
      {
        'patientUserId': 'patient-a',
        'status': 'active',
        'presentationType': 'partner',
        'notificationPreferences': {
          'enabled': false,
          'missedAlertsEnabled': true,
          'careEventsEnabled': true,
        },
      },
    ];

    expect(
      CareNotificationProvider.allowsMissedForRelationships(
        relationships,
        patientUserId: 'patient-a',
      ),
      isFalse,
    );
    expect(
      CareNotificationProvider.allowsReminderForRelationships(
        relationships,
        patientUserId: 'patient-a',
        kind: 'appointment',
      ),
      isFalse,
    );
  });

  test('unknown relationship keeps neutral notification copy', () {
    const summary = CareDailySummary(
      patientUserId: 'patient-a',
      patientDisplayName: 'Alex',
      total: 1,
      completed: 1,
      pending: 0,
      alerts: 0,
    );
    final copy = CareNotificationProvider.dailySummaryCopy(
      summary,
      isPersian: false,
      relationshipType: 'old-unknown-value',
    );
    expect(copy.title, '☀️ Today for Alex');
  });
}
