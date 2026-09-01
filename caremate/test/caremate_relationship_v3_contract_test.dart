import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CareMate root is gated by server relationship state', () {
    final root = File('lib/screens/caremate_root_shell.dart').readAsStringSync();
    final gate = File(
      'lib/screens/onboarding/caremate_relationship_v3_gate.dart',
    ).readAsStringSync();

    expect(root, contains('CareMateRelationshipV3Gate'));
    expect(gate, contains('getCurrentUser()'));
    expect(gate, contains('getCareRelationships()'));
    expect(gate, contains("status == 'active'"));
    expect(gate, contains('_CareMateGatePhase.pending'));
    expect(gate, contains('_CareMateGatePhase.revoked'));
  });

  test('pairing reuses canonical scanner and invitation acceptance', () {
    final gate = File(
      'lib/screens/onboarding/caremate_relationship_v3_gate.dart',
    ).readAsStringSync();

    expect(gate, contains('CareInvitationScannerScreen'));
    expect(gate, contains('acceptCareInvitation'));
    expect(gate, contains('LifeMateOnboardingTheme.careMate'));
    expect(gate, contains('LifeMateOnboardingScaffold'));
    expect(gate, isNot(contains('SharedPreferences')));
    expect(gate, isNot(contains('Hive')));
    expect(gate, isNot(contains('SingleChildScrollView')));
    expect(gate, isNot(contains('ListView')));
  });

  test('relationship type is presentation-only and not an authorization input', () {
    final gate = File(
      'lib/screens/onboarding/caremate_relationship_v3_gate.dart',
    ).readAsStringSync();

    expect(gate, contains("preview['relationshipType']"));
    expect(gate, contains('LifeMateRelationshipPresentationPolicy.fromRaw'));
    expect(
      gate,
      contains(
        'Relationship type only personalizes CareMate presentation and never grants sensitive access.',
      ),
    );
    expect(gate, contains('acceptCareInvitation(token: normalizedToken)'));
    expect(gate, isNot(contains("'relationshipType':")));
    expect(gate, isNot(contains("'relationshipHint':")));
  });

  test('pending state does not mount dashboard or load health data', () {
    final gate = File(
      'lib/screens/onboarding/caremate_relationship_v3_gate.dart',
    ).readAsStringSync();

    expect(
      gate,
      contains(
        'No health data is shown until the relationship and both consents are active.',
      ),
    );
    expect(gate, isNot(contains('CareHomeAggregator')));
    expect(gate, isNot(contains('getCareRecipientDoseOccurrences')));
    expect(gate, isNot(contains('getCareRecipientCareEvents')));
  });

  test('fertility scopes are exact, independent and fail closed', () {
    final gate = File(
      'lib/screens/onboarding/caremate_relationship_v3_gate.dart',
    ).readAsStringSync();

    expect(gate, contains("_privacyScopes['viewFertilityEstimate'] == true"));
    expect(
      gate,
      contains("_privacyScopes['receiveFertilityNotifications'] == true"),
    );
    expect(gate, contains("'viewFertilityEstimate': false"));
    expect(gate, contains("'receiveFertilityNotifications': false"));
    expect(gate, contains('getCareRecipientWomenCalendar'));
  });

  test('backend invitation contract denies invalid, expired, wrong and self use', () {
    final source = File(
      '../supabase/functions/lifemate-api/person_invitation_acceptance.ts',
    ).readAsStringSync();

    expect(source, contains('invitation_not_found'));
    expect(source, contains('invitation_expired'));
    expect(source, contains('invitation_contact_mismatch'));
    expect(source, contains('invitation_not_pending'));
    expect(source, contains('self_invitation_not_allowed'));
    expect(source, contains('timingSafeEqual'));
  });

  test('care dashboard still fails closed to active caregiver relationships', () {
    final aggregator = File(
      'lib/services/care_home_aggregator.dart',
    ).readAsStringSync();

    expect(
      aggregator,
      contains("value['status']?.toString().toLowerCase() == 'active'"),
    );
    expect(aggregator, contains('.canViewWomenCalendar'));
    expect(aggregator, contains('women_calendar_access_denied'));
    expect(aggregator, contains('CareCompanionHomeSummary.locked()'));
  });

  test('relationship presentation never replaces authorization checks', () {
    final aggregator = File(
      'lib/services/care_home_aggregator.dart',
    ).readAsStringSync();
    final notifications = File(
      'lib/providers/care_notification_provider.dart',
    ).readAsStringSync();
    final backend = File(
      '../supabase/functions/lifemate-api/person_care_relationship_management.ts',
    ).readAsStringSync();

    expect(aggregator, contains('surfaceRank'));
    expect(aggregator, contains('.canViewWomenCalendar'));
    expect(notifications, contains('allowsReminderForRelationships'));
    expect(notifications, contains('allowsMissedForRelationships'));
    expect(backend, contains('care_relationship.presentation_updated'));
    expect(
      backend,
      isNot(contains('caregiver_relationship_type = can_view_women_calendar')),
    );
  });
}
