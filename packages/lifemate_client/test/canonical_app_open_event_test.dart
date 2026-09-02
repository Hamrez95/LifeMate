import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test('authenticated app-open telemetry uses the canonical app_opened taxonomy name', () {
    final event = PrivacySafeProductEvent.create(
      application: 'WellMate',
      releaseVersion: '0.9.0',
      event: LifeMateProductEvent.appOpen,
      outcome: LifeMateTelemetryOutcome.success,
    );

    expect(event.eventName, 'app_opened');
    expect(event.toJson().keys.toSet(), <String>{
      'kind',
      'eventId',
      'application',
      'releaseVersion',
      'platform',
      'eventName',
      'localeFamily',
      'connectivity',
      'outcome',
    });
  });
}
