import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

import 'package:caremate/models/care_home_snapshot.dart';
import 'package:caremate/services/companion_care_engine.dart';
import 'package:caremate/widgets/companion_care_guidance_card.dart';

void main() {
  final summary = CareCompanionHomeSummary(
    hasPermission: true,
    available: true,
    relationship: const CareHomeRelationship(
      relationshipId: 'rel-1',
      patientUserId: 'patient-1',
      patientDisplayName: 'Partner',
      canViewWomenCalendar: false,
    ),
    wellbeingAllowed: true,
    mood: 'low',
    energyLevel: 4,
  );

  testWidgets('renders non-diagnostic localized guidance', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompanionCareGuidanceCard(
            summary: summary,
            isPersian: false,
            font: const TextStyle(),
            onRevoked: () {},
            onSupportRequested: () {},
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('companion-care-guidance-card')), findsOneWidget);
    expect(find.text('A gentle check-in'), findsOneWidget);
    expect(find.textContaining('not a diagnosis'), findsOneWidget);
  });

  testWidgets('403 impression revoke removes personalized card immediately', (tester) async {
    var revoked = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompanionCareGuidanceCard(
            summary: summary,
            isPersian: false,
            font: const TextStyle(),
            onRevoked: () => revoked = true,
            onSupportRequested: () {},
            recordImpression: (CompanionCareGuidance guidance) async {
              throw const LifeMateApiException(
                statusCode: 403,
                code: 'women_calendar_access_denied',
                message: 'revoked',
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();

    expect(revoked, isTrue);
    expect(find.byKey(const ValueKey('companion-care-guidance-card')), findsNothing);
  });
}
