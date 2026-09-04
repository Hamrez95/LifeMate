import 'package:cocoonmate/app/cocoon_standalone_app.dart';
import 'package:cocoonmate_module/cocoonmate_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  const configured = AppConfig(
    supabaseUrl: 'https://example.supabase.co',
    supabasePublishableKey: 'sb_publishable_test',
    apiBaseUrl: 'https://api.example.test',
  );

  test('Cocoon auth callback has an isolated app scheme', () {
    expect(
      LifeMateAuth.callbackUrlForApp('CocoonMate'),
      'com.mylifemate.cocoonmate://login-callback/',
    );
  });

  test('bootstrap state keeps enrollment commerce and pregnancy separate', () {
    expect(
      resolveCocoonEntryState(_snapshot(enrollment: 'not_enrolled')),
      CocoonEntryState.notEnrolled,
    );
    expect(
      resolveCocoonEntryState(_snapshot(entitlement: 'inactive')),
      CocoonEntryState.notEntitled,
    );
    expect(
      resolveCocoonEntryState(_snapshot(activePregnancy: false)),
      CocoonEntryState.noPregnancy,
    );
    expect(
      resolveCocoonEntryState(_snapshot()),
      CocoonEntryState.activePregnancy,
    );
  });

  test('authoritative dependency failure never unlocks Cocoon', () {
    expect(
      resolveCocoonEntryState(_snapshot(commerce: 'error')),
      CocoonEntryState.runtimeUnavailable,
    );
    expect(
      resolveCocoonEntryState(_snapshot(availability: 'unavailable')),
      CocoonEntryState.runtimeUnavailable,
    );
  });

  testWidgets(
    'authenticated host mounts module and resolves active pregnancy',
    (tester) async {
      final now = DateTime.now().toUtc();
      await tester.pumpWidget(
        MaterialApp(
          home: CocoonAuthenticatedHost(
            config: configured,
            locale: const Locale('en'),
            runtimeLoader: () async => LifeMateRuntimeConfigSnapshot(
              product: 'cocoonmate',
              platform: 'android',
              controls: const {},
              updatePolicy: const LifeMateUpdatePolicy(
                state: LifeMateUpdateState.current,
                minimumSupportedVersion: null,
                recommendedVersion: null,
                reasonCode: 'Routine',
                messageKey: null,
                policyVersion: 1,
              ),
              snapshotVersion: 'test',
              fetchedAtUtc: now,
              cacheTtlSeconds: 60,
              fromCache: false,
            ),
            bootstrapLoader: () async => _snapshot(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byType(CocoonMateModule), findsOneWidget);
      expect(find.text('Home'), findsWidgets);
    },
  );
}

CocoonBootstrapSnapshot _snapshot({
  String enrollment = 'active',
  String entitlement = 'active',
  String commerce = 'entitled',
  String availability = 'available',
  bool activePregnancy = true,
}) {
  return CocoonBootstrapSnapshot.fromJson({
    'contractVersion': 1,
    'subject': {'personId': '00000000-0000-0000-0000-000000000001'},
    'enrollmentState': activePregnancy ? 'active' : 'not_enrolled',
    'entitlementState': {'state': entitlement},
    'applicationState': {
      'availability': availability,
      'enrollmentState': enrollment,
    },
    'commerceEligibility': {
      'state': commerce,
      'offerAvailable': commerce == 'offer_available',
      'conversionEligible': commerce == 'conversion_eligible',
    },
    if (activePregnancy)
      'activeEpisode': {
        'id': '00000000-0000-0000-0000-000000000002',
        'motherPersonId': '00000000-0000-0000-0000-000000000001',
        'status': 'active',
        'dating': {},
        'version': 1,
      },
    'runtime': {
      'serverAuthoritativeSharing': true,
      'serverAuthoritativeEntitlementActivation': true,
      'cachedOwnerSnapshotAllowed': true,
      'cachedSharedSnapshotAllowed': false,
    },
  });
}
