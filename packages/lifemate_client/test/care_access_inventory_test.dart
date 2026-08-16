import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

class _FakeCareApi extends LifeMateApiClient {
  _FakeCareApi({required this.patientMode})
      : super(
          baseUri: Uri.parse('https://api.example.test'),
          accessToken: () => 'test-token',
        );

  final bool patientMode;
  var revokeCalls = 0;
  var active = true;

  @override
  Future<Map<String, dynamic>> getCurrentUser() async => <String, dynamic>{
        'user': <String, dynamic>{
          'id': patientMode ? 'patient-1' : 'caregiver-1',
        },
      };

  @override
  Future<List<Map<String, dynamic>>> getCareRelationships() async => [
        <String, dynamic>{
          'id': 'relationship-active',
          'status': active ? 'active' : 'revoked',
          'patientUserId': 'patient-1',
          'caregiverUserId': 'caregiver-1',
          'patientDisplayName': 'Patient One',
          'caregiverDisplayName': 'Caregiver One',
          'createdAtUtc': '2026-08-15T08:00:00Z',
          if (!active) 'revokedAtUtc': '2026-08-16T08:00:00Z',
          'healthPayload': 'PRIVATE_HEALTH_PAYLOAD',
        },
        <String, dynamic>{
          'id': 'relationship-old',
          'status': 'revoked',
          'patientUserId': 'patient-1',
          'caregiverUserId': 'caregiver-1',
          'patientDisplayName': 'Previous Patient',
          'caregiverDisplayName': 'Previous Caregiver',
          'revokedAtUtc': '2026-08-14T08:00:00Z',
          'rawToken': 'PRIVATE_RAW_TOKEN',
        },
      ];

  @override
  Future<List<Map<String, dynamic>>> getOutgoingCareInvitations() async => [
        <String, dynamic>{
          'id': 'invitation-pending',
          'status': 'pending',
          'contactHint': 'c***@example.test',
          'createdAtUtc': '2026-08-16T07:00:00Z',
          'rawToken': 'PRIVATE_INVITATION_TOKEN',
        },
        <String, dynamic>{
          'id': 'invitation-expired',
          'status': 'expired',
          'contactHint': 'o***@example.test',
          'expiresAtUtc': '2026-08-15T07:00:00Z',
        },
      ];

  @override
  Future<List<Map<String, dynamic>>> getIncomingCareRequests() async => [
        <String, dynamic>{
          'id': 'request-rejected',
          'status': 'rejected',
          'requesterDisplayName': 'Rejected Requester',
          'respondedAtUtc': '2026-08-13T07:00:00Z',
          'healthPayload': 'PRIVATE_REQUEST_HEALTH',
        },
      ];

  @override
  Future<List<Map<String, dynamic>>> getOutgoingCareRequests() async => [
        <String, dynamic>{
          'id': 'care-request-pending',
          'status': 'pending',
          'contactHint': 'p***@example.test',
          'createdAtUtc': '2026-08-16T07:00:00Z',
        },
        <String, dynamic>{
          'id': 'care-request-rejected',
          'status': 'rejected',
          'contactHint': 'r***@example.test',
          'respondedAtUtc': '2026-08-13T07:00:00Z',
        },
      ];

  @override
  Future<void> revokeCareRelationship({required String relationshipId}) async {
    revokeCalls += 1;
    active = false;
  }
}

Future<void> _pumpInventory(
  WidgetTester tester,
  _FakeCareApi api,
  LifeMateCareAccessRole role,
) async {
  LifeMateRuntimeLocale.setLanguageCode('en');
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      home: LifeMateCareAccessInventoryScreen(
        apiClient: api,
        role: role,
        accent: Colors.blue,
        background: const Color(0xFFF7F8FA),
        ink: const Color(0xFF172033),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() => LifeMateRuntimeLocale.setLanguageCode('fa'));

  testWidgets('patient inventory separates active pending and closed history',
      (tester) async {
    final api = _FakeCareApi(patientMode: true);
    await _pumpInventory(tester, api, LifeMateCareAccessRole.patient);

    expect(find.text('Active caregivers'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Access history'), findsOneWidget);
    expect(find.text('Caregiver One'), findsOneWidget);
    expect(find.text('c***@example.test'), findsOneWidget);
    expect(find.text('Previous Caregiver'), findsOneWidget);
    expect(find.text('Rejected Requester'), findsOneWidget);
    expect(find.textContaining('PRIVATE_HEALTH_PAYLOAD'), findsNothing);
    expect(find.textContaining('PRIVATE_RAW_TOKEN'), findsNothing);
    expect(find.textContaining('PRIVATE_INVITATION_TOKEN'), findsNothing);
    expect(find.textContaining('PRIVATE_REQUEST_HEALTH'), findsNothing);
  });

  testWidgets('caregiver inventory shows care recipients and request history',
      (tester) async {
    final api = _FakeCareApi(patientMode: false);
    await _pumpInventory(tester, api, LifeMateCareAccessRole.caregiver);

    expect(find.text('Active care recipients'), findsOneWidget);
    expect(find.text('Patient One'), findsOneWidget);
    expect(find.text('p***@example.test'), findsOneWidget);
    expect(find.text('r***@example.test'), findsOneWidget);
    expect(find.text('Access history'), findsOneWidget);
  });

  testWidgets('revocation confirms once and refreshes relationship into history',
      (tester) async {
    final api = _FakeCareApi(patientMode: true);
    await _pumpInventory(tester, api, LifeMateCareAccessRole.patient);

    await tester.tap(find.byTooltip('Revoke access').first);
    await tester.pumpAndSettle();
    expect(find.text('Revoke access?'), findsOneWidget);
    await tester.tap(find.text('Revoke'));
    await tester.pumpAndSettle();

    expect(api.revokeCalls, 1);
    expect(find.text('Caregiver One'), findsOneWidget);
    expect(find.text('Active caregivers'), findsOneWidget);
    expect(find.text('0'), findsWidgets);
    expect(find.text('Revoked'), findsWidgets);
  });
}
