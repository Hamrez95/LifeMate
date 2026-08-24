import 'package:caremate/providers/care_notification_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const relationships = <Map<String, dynamic>>[
    {
      'patientUserId': 'patient-a',
      'status': 'active',
      'notificationPreferences': {
        'enabled': true,
        'missedAlertsEnabled': false,
        'careEventsEnabled': true,
        'lockScreenDetail': 'limited',
      },
    },
    {
      'patientUserId': 'patient-b',
      'status': 'active',
      'notificationPreferences': {
        'enabled': true,
        'missedAlertsEnabled': true,
        'careEventsEnabled': false,
        'lockScreenDetail': 'hidden',
      },
    },
    {
      'patientUserId': 'patient-c',
      'status': 'active',
      'notificationPreferences': {
        'enabled': false,
        'missedAlertsEnabled': true,
        'careEventsEnabled': true,
      },
    },
  ];

  test('missed preference is isolated per person', () {
    expect(
      CareNotificationProvider.allowsMissedForRelationships(
        relationships,
        patientUserId: 'patient-a',
      ),
      isFalse,
    );
    expect(
      CareNotificationProvider.allowsMissedForRelationships(
        relationships,
        patientUserId: 'patient-b',
      ),
      isTrue,
    );
    expect(
      CareNotificationProvider.allowsMissedForRelationships(
        relationships,
        patientUserId: 'patient-c',
      ),
      isFalse,
    );
  });

  test('care-event preference does not disable medication reminders', () {
    expect(
      CareNotificationProvider.allowsReminderForRelationships(
        relationships,
        patientUserId: 'patient-b',
        kind: 'appointment',
      ),
      isFalse,
    );
    expect(
      CareNotificationProvider.allowsReminderForRelationships(
        relationships,
        patientUserId: 'patient-b',
        kind: 'medication',
      ),
      isTrue,
    );
  });

  test('unknown or inactive person fails closed', () {
    expect(
      CareNotificationProvider.allowsMissedForRelationships(
        relationships,
        patientUserId: 'unknown',
      ),
      isFalse,
    );
  });
}
