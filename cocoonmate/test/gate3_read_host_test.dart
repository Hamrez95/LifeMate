import 'package:cocoonmate/app/cocoon_gate3_read_models.dart';
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

  testWidgets(
    'active pregnancy binds canonical Calendar and Records read models',
    (tester) async {
      var readCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: CocoonTheme.light(),
          home: CocoonAuthenticatedHost(
            config: configured,
            locale: const Locale('en'),
            runtimeLoader: () async => _validRuntime(),
            bootstrapLoader: () async => _snapshot(),
            gate3ReadLoader: ({required now, required fa}) async {
              readCalls++;
              expect(fa, isFalse);
              return CocoonGate3ReadModels(
                calendarState: CocoonCalendarLoadState.populated,
                calendarItems: const [
                  CocoonCalendarItem(
                    id: 'series-1',
                    title: 'Canonical prenatal appointment',
                    dateLabel: '2026-09-20',
                    timeLabel: '10:30',
                    kind: CocoonCalendarItemKind.appointment,
                  ),
                ],
                calendarAsOfLocalDate: DateTime(2026, 9, 16),
                recordsState: CocoonRecordsState.ready,
                records: const [
                  CocoonRecordViewData(
                    id: 'treatment_plan:plan-1',
                    title: 'Treatment plan',
                    dateLabel: '2026-09-15',
                    sectionLabel: '2026-09-15',
                    summary: 'Active',
                    kind: CocoonRecordKind.medication,
                    syncState: CocoonRecordSyncState.confirmed,
                  ),
                ],
              );
            },
          ),
        ),
      );

      await tester.pump();
      await tester.pumpAndSettle();
      expect(readCalls, 1);

      await tester.tap(find.text('Calendar'));
      await tester.pumpAndSettle();
      expect(find.text('Canonical prenatal appointment'), findsOneWidget);

      await tester.tap(find.text('Records'));
      await tester.pumpAndSettle();
      expect(find.text('Treatment plan'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Gate-3 read loader never runs without an active pregnancy', (
    tester,
  ) async {
    var readCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: CocoonTheme.light(),
        home: CocoonAuthenticatedHost(
          config: configured,
          locale: const Locale('en'),
          runtimeLoader: () async => _validRuntime(),
          bootstrapLoader: () async => _snapshot(activePregnancy: false),
          gate3ReadLoader: ({required now, required fa}) async {
            readCalls++;
            throw StateError('must not load Gate-3 without an active episode');
          },
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();
    expect(readCalls, 0);
    expect(find.text('No active pregnancy yet'), findsOneWidget);
  });
}

LifeMateRuntimeConfigSnapshot _validRuntime() {
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
    snapshotVersion: 'gate-3-read-test',
    fetchedAtUtc: DateTime.now().toUtc(),
    cacheTtlSeconds: 60,
    fromCache: false,
  );
}

CocoonBootstrapSnapshot _snapshot({bool activePregnancy = true}) {
  const personId = '00000000-0000-0000-0000-000000000001';
  return CocoonBootstrapSnapshot.fromJson({
    'contractVersion': 1,
    'subject': {'personId': personId},
    'enrollmentState': activePregnancy ? 'active' : 'not_enrolled',
    'entitlementState': {'state': 'active'},
    'applicationState': {
      'availability': 'available',
      'enrollmentState': activePregnancy ? 'active' : 'not_enrolled',
    },
    'commerceEligibility': {
      'state': 'entitled',
      'offerAvailable': false,
      'conversionEligible': false,
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
