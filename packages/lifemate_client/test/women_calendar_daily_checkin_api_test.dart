import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test('daily wellbeing uses only the canonical daily-log endpoint', () async {
    late http.Request observed;
    final api = WomenCompanionApi(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'access-token',
      httpClient: MockClient((request) async {
        observed = request;
        return http.Response(
          jsonEncode({
            'id': 'log-1',
            'loggedOn': '2026-08-05',
            'mood': 'good',
            'energyLevel': 4,
            'painLevel': 2,
            'symptoms': ['fatigue'],
            'privateNotes': 'یادداشت خصوصی',
            'shareSummaryWithCompanion': true,
            'version': 1,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await api.saveDailyLog(
      version: 0,
      loggedOn: DateTime(2026, 8, 5),
      mood: 'good',
      energyLevel: 4,
      painLevel: 2,
      symptoms: const ['fatigue'],
      privateNotes: 'یادداشت خصوصی',
      shareSummaryWithCompanion: true,
    );

    expect(observed.method, 'PUT');
    expect(observed.url.path, '/api/v1/women-calendar/daily-logs');
    final payload = jsonDecode(observed.body) as Map<String, dynamic>;
    expect(payload['loggedOn'], '2026-08-05');
    expect(payload['energyLevel'], 4);
    expect(payload['painLevel'], 2);
    expect(payload.containsKey('supportNeed'), isFalse);
  });

  test('settings-only update has no daily state field', () async {
    late http.Request observed;
    final api = LifeMateApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'access-token',
      httpClient: MockClient((request) async {
        observed = request;
        return http.Response(
          jsonEncode({
            'ownerUserId': 'owner-1',
            'enabled': true,
            'lastPeriodStart': '2026-08-01',
            'cycleLength': 30,
            'periodLength': 6,
            'remindersEnabled': false,
            'version': 5,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await api.updateWomenCalendarProfile(
      version: 4,
      enabled: true,
      lastPeriodStart: DateTime(2026, 8, 1),
      cycleLength: 30,
      periodLength: 6,
      remindersEnabled: false,
    );

    final payload = jsonDecode(observed.body) as Map<String, dynamic>;
    expect(payload.containsKey('dailyCheckIn'), isFalse);
  });

  test('care support action uses patient-scoped authorized route', () async {
    late http.Request observed;
    final api = LifeMateApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'caregiver-token',
      httpClient: MockClient((request) async {
        observed = request;
        return http.Response(
          jsonEncode({
            'id': 'action-1',
            'actionType': 'hug',
            'performedAtUtc': '2026-08-05T19:00:00Z',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await api.recordCareRecipientWomenSupportAction(
      patientUserId: 'patient-1',
      actionType: ' hug ',
    );

    expect(observed.method, 'POST');
    expect(
      observed.url.path,
      '/api/v1/care/patients/patient-1/women-calendar/support-actions',
    );
    expect(jsonDecode(observed.body), {'actionType': 'hug'});
  });
}
