import 'package:cocoonmate/app/cocoon_gate3_mutations.dart';
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

  testWidgets('transport failure stays visibly queued, never confirmed', (
    tester,
  ) async {
    String? onlineId;
    String? queuedId;
    final mutation = _mutation(
      submitCheckInOnline: ({
        required clientRequestId,
        required observedAtUtc,
        required localDate,
        required timeZone,
        required feeling,
        required energy,
      }) async {
        onlineId = clientRequestId;
        throw const LifeMateApiException(
          statusCode: 0,
          code: 'network_unavailable',
          message: 'offline',
        );
      },
      enqueueCheckInOffline: ({
        required clientRequestId,
        required observedAtUtc,
        required localDate,
        required feeling,
        required energy,
      }) async {
        queuedId = clientRequestId;
      },
    );

    await _pumpHost(tester, configured, mutation);
    await _openAndSubmitCheckIn(tester);

    expect(onlineId, isNotNull);
    expect(queuedId, onlineId);
    expect(find.text('Queued; not yet server-confirmed'), findsOneWidget);
    expect(find.text('Saved and server-confirmed'), findsNothing);
  });

  testWidgets('online success refreshes reads before confirmed presentation', (
    tester,
  ) async {
    var readCalls = 0;
    final mutation = _mutation();

    await _pumpHost(
      tester,
      configured,
      mutation,
      readLoader: ({required now, required fa}) async {
        readCalls++;
        return _emptyReads(now);
      },
    );
    expect(readCalls, 1);

    await _openAndSubmitCheckIn(tester);

    expect(readCalls, 2);
    expect(find.text('Saved and server-confirmed'), findsOneWidget);
  });
}

Future<void> _pumpHost(
  WidgetTester tester,
  AppConfig configured,
  CocoonGate3MutationAdapter mutation, {
  CocoonGate3ReadLoader? readLoader,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: CocoonTheme.light(),
      home: CocoonAuthenticatedHost(
        config: configured,
        locale: const Locale('en'),
        runtimeLoader: () async => _validRuntime(),
        bootstrapLoader: () async => _snapshot(),
        gate3ReadLoader:
            readLoader ??
            ({required now, required fa}) async => _emptyReads(now),
        gate3MutationAdapter: mutation,
        offlineBootstrapCache: (_) async {},
      ),
    ),
  );
  await tester.pump();
  await tester.pumpAndSettle();
}

Future<void> _openAndSubmitCheckIn(WidgetTester tester) async {
  await tester.tap(find.text('Add'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Today’s check-in'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Comfortable'));
  await tester.tap(find.text('Steady'));
  await tester.pump();
  await tester.tap(find.text('Save today’s check-in'));
  await tester.pumpAndSettle();
}

CocoonGate3MutationAdapter _mutation({
  CocoonGate3CheckInOnlineSubmit? submitCheckInOnline,
  CocoonGate3CheckInOfflineEnqueue? enqueueCheckInOffline,
}) {
  return CocoonGate3MutationAdapter(
    timeZone: 'Asia/Tehran',
    requestIdFactory: () => '123e4567-e89b-42d3-a456-426614174000',
    clock: () => DateTime(2026, 9, 16, 12),
    submitCheckInOnline:
        submitCheckInOnline ??
        ({
          required clientRequestId,
          required observedAtUtc,
          required localDate,
          required timeZone,
          required feeling,
          required energy,
        }) async {},
    enqueueCheckInOffline:
        enqueueCheckInOffline ??
        ({
          required clientRequestId,
          required observedAtUtc,
          required localDate,
          required feeling,
          required energy,
        }) async {},
    submitMeasurementOnline: ({
      required clientRequestId,
      required type,
      required valuePrimary,
      valueSecondary,
      note,
      required observedAtUtc,
      required observedLocalDate,
      required timeZone,
    }) async {},
    enqueueMeasurementOffline: ({
      required clientRequestId,
      required observationType,
      required valuePrimary,
      valueSecondary,
      note,
      required observedAtUtc,
      required observedLocalDate,
    }) async {},
  );
}

CocoonGate3ReadModels _emptyReads(DateTime now) => CocoonGate3ReadModels(
  calendarState: CocoonCalendarLoadState.empty,
  calendarItems: const [],
  calendarAsOfLocalDate: DateTime(now.year, now.month, now.day),
  recordsState: CocoonRecordsState.empty,
  records: const [],
);

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
    snapshotVersion: 'gate-3-quickadd-test',
    fetchedAtUtc: DateTime.now().toUtc(),
    cacheTtlSeconds: 60,
    fromCache: false,
  );
}

CocoonBootstrapSnapshot _snapshot() {
  const personId = '00000000-0000-0000-0000-000000000001';
  return CocoonBootstrapSnapshot.fromJson({
    'contractVersion': 1,
    'subject': {'personId': personId},
    'enrollmentState': 'active',
    'entitlementState': {'state': 'active'},
    'applicationState': {
      'availability': 'available',
      'enrollmentState': 'active',
    },
    'commerceEligibility': {
      'state': 'entitled',
      'offerAvailable': false,
      'conversionEligible': false,
    },
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
