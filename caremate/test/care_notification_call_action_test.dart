import 'package:caremate/providers/care_notification_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resolves phone only for the matching active patient relationship', () {
    final phone = CareNotificationProvider.resolveAuthorizedPatientPhone(
      const [
        {
          'patientUserId': 'patient-a',
          'status': 'active',
          'patientPhoneNumber': '+989121111111',
        },
        {
          'patientUserId': 'patient-b',
          'status': 'active',
          'patientPhoneNumber': '+989122222222',
        },
      ],
      patientUserId: 'patient-b',
    );

    expect(phone, '+989122222222');
  });

  test('revoked or missing phone never produces a call target', () {
    expect(
      CareNotificationProvider.resolveAuthorizedPatientPhone(
        const [
          {
            'patientUserId': 'patient-a',
            'status': 'revoked',
            'patientPhoneNumber': '+989121111111',
          },
        ],
        patientUserId: 'patient-a',
      ),
      isNull,
    );
    expect(
      CareNotificationProvider.resolveAuthorizedPatientPhone(
        const [
          {'patientUserId': 'patient-a', 'status': 'active'},
        ],
        patientUserId: 'patient-a',
      ),
      isNull,
    );
  });

  test('unrelated patient never resolves another persons phone', () {
    final phone = CareNotificationProvider.resolveAuthorizedPatientPhone(
      const [
        {
          'patientUserId': 'patient-a',
          'status': 'active',
          'patientPhoneNumber': '+989121111111',
        },
      ],
      patientUserId: 'patient-z',
    );

    expect(phone, isNull);
  });
}
