import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('runtime registers the contextual notification provider', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains('ContextualNotificationProvider()'));
    expect(
      main,
      contains('ChangeNotifierProvider<NotificationProvider>.value'),
    );
    expect(main, contains('WellMateFirstValueGate('));
  });

  test('background reminder sync is blocked before explicit permission flow', () {
    final source = File(
      'lib/providers/contextual_notification_provider.dart',
    ).readAsStringSync();
    expect(source, contains('if (!_nativePermissionFlowUnlocked) return;'));
    expect(source, contains('requestAfterExplanation()'));
    expect(source, contains('requestNotificationsPermission()'));
    expect(source, contains('requestExactAlarmsPermission()'));
    expect(source, contains('areNotificationsEnabled()'));
  });

  test('durable care-event cursor waits for reminder reconciliation', () {
    final source = File(
      'lib/providers/contextual_notification_provider.dart',
    ).readAsStringSync();
    final nativeBridge = File(
      'lib/providers/care_event_projection_sync_bridge_native.dart',
    ).readAsStringSync();
    final webBridge = File(
      'lib/providers/care_event_projection_sync_bridge_web.dart',
    ).readAsStringSync();

    expect(source, contains('syncOwnerCareEventProjectionsIfSupported('));
    expect(source, contains('_reconcileAffectedCareEvents('));
    expect(source, contains('await super.syncReminders('));
    expect(source, contains('_projectionSyncInFlight'));
    expect(source, contains("item.type == 'medicine'"));

    expect(nativeBridge, contains('apiClient is! DurableLifeMateApiClient'));
    expect(nativeBridge, contains('apiClient.syncCareEventProjections('));
    expect(nativeBridge, contains('staged.affectedRecordKeys'));
    expect(webBridge, isNot(contains('DurableLifeMateApiClient')));
  });

  test('first-value wrapper reuses canonical treatment form and stays no-scroll', () {
    final gate = File(
      'lib/screens/onboarding/wellmate_first_value_gate.dart',
    ).readAsStringSync();
    expect(gate, contains('TabbedAddTreatmentScreen('));
    expect(gate, contains('LifeMateOnboardingScaffold('));
    expect(gate, isNot(contains('SingleChildScrollView')));
    expect(gate, isNot(contains('ListView(')));
    expect(gate, contains("state: 'Completed'"));
    expect(gate, contains("state: 'Skipped'"));
    expect(gate, contains('getTreatmentPlans()'));
  });
}
