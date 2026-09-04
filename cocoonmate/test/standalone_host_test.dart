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

  test('missing Person and app unavailability fail closed', () {
    expect(
      resolveCocoonEntryState(_snapshot(personId: '')),
      CocoonEntryState.runtimeUnavailable,
    );
    expect(
      resolveCocoonEntryState(_snapshot(availability: 'unavailable')),
      CocoonEntryState.runtimeUnavailable,
    );
  });

  test('unknown entitlement and unavailable Commerce never unlock Cocoon', () {
    for (final commerce in ['unknown', 'unavailable', 'error']) {
      expect(
        resolveCocoonEntryState(_snapshot(commerce: commerce)),
        CocoonEntryState.runtimeUnavailable,
      );
    }
    expect(
      resolveCocoonEntryState(_snapshot(entitlement: 'unknown')),
      CocoonEntryState.runtimeUnavailable,
    );
  });

  test(
    'active entitlement alone cannot bypass Cocoon Commerce eligibility',
    () {
      expect(
        resolveCocoonEntryState(
          _snapshot(entitlement: 'active', commerce: 'offer_available'),
        ),
        CocoonEntryState.notEntitled,
      );
      expect(
        resolveCocoonEntryState(
          _snapshot(entitlement: 'active', commerce: 'conversion_eligible'),
        ),
        CocoonEntryState.notEntitled,
      );
    },
  );

  testWidgets(
    'authenticated host mounts module and resolves active pregnancy',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CocoonAuthenticatedHost(
            config: configured,
            locale: const Locale('en'),
            runtimeLoader: () async => _validRuntime(),
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

  testWidgets('network failure routes to the offline gate', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CocoonAuthenticatedHost(
          config: configured,
          locale: const Locale('en'),
          runtimeLoader: () async => _validRuntime(),
          bootstrapLoader: () async => throw const LifeMateApiException(
            statusCode: 0,
            code: 'network_unavailable',
            message: 'Network unavailable',
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('You are offline'), findsOneWidget);
  });

  testWidgets('expired session signs out and returns to auth gate', (
    tester,
  ) async {
    var signedOut = false;
    await tester.pumpWidget(
      MaterialApp(
        home: CocoonAuthenticatedHost(
          config: configured,
          locale: const Locale('en'),
          runtimeLoader: () async => _validRuntime(),
          bootstrapLoader: () async => throw const LifeMateApiException(
            statusCode: 401,
            code: 'unauthorized',
            message: 'Session expired',
          ),
          signOut: () async {
            signedOut = true;
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(signedOut, isTrue);
    expect(find.text('Sign in to continue'), findsOneWidget);
  });

  testWidgets('runtime failure never falls through to product content', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CocoonAuthenticatedHost(
          config: configured,
          locale: const Locale('en'),
          runtimeLoader: () async => throw const FormatException('invalid'),
          bootstrapLoader: () async => _snapshot(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('CocoonMate is temporarily unavailable'), findsOneWidget);
    expect(find.text('Home'), findsNothing);
  });

  testWidgets('untrusted stale runtime config fails closed', (tester) async {
    final stale = _validRuntime(
      fetchedAtUtc: DateTime.now().toUtc().subtract(const Duration(days: 30)),
      cacheTtlSeconds: 1,
      fromCache: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CocoonAuthenticatedHost(
          config: configured,
          locale: const Locale('en'),
          runtimeLoader: () async => stale,
          bootstrapLoader: () async => _snapshot(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('CocoonMate is temporarily unavailable'), findsOneWidget);
  });

  testWidgets('no-pregnancy setup control does not fabricate local episode', (
    tester,
  ) async {
    var bootstrapCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: CocoonAuthenticatedHost(
          config: configured,
          locale: const Locale('en'),
          runtimeLoader: () async => _validRuntime(),
          bootstrapLoader: () async {
            bootstrapCalls++;
            return _snapshot(activePregnancy: false);
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('No active pregnancy yet'), findsOneWidget);
    await tester.tap(find.text('Start setup'));
    await tester.pump();
    expect(find.text('No active pregnancy yet'), findsOneWidget);
    expect(bootstrapCalls, 1);
  });
}

LifeMateRuntimeConfigSnapshot _validRuntime({
  DateTime? fetchedAtUtc,
  int cacheTtlSeconds = 60,
  bool fromCache = false,
}) {
  return LifeMateRuntimeConfigSnapshot(
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
    snapshotVersion: 'gate-1-test',
    fetchedAtUtc: fetchedAtUtc ?? DateTime.now().toUtc(),
    cacheTtlSeconds: cacheTtlSeconds,
    fromCache: fromCache,
  );
}

CocoonBootstrapSnapshot _snapshot({
  String personId = '00000000-0000-0000-0000-000000000001',
  String enrollment = 'active',
  String entitlement = 'active',
  String commerce = 'entitled',
  String availability = 'available',
  bool activePregnancy = true,
}) {
  return CocoonBootstrapSnapshot.fromJson({
    'contractVersion': 1,
    'subject': {'personId': personId},
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
        'motherPersonId': personId,
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
