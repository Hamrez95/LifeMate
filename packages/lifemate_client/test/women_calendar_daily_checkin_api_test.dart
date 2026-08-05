import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test('daily check-in sends the explicit private owner payload', () async {
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
            'cycleLength': 28,
            'periodLength': 5,
            'remindersEnabled': true,
            'version': 4,
            'dailyCheckIn': {
              'date': '2026-08-05',
              'mood': 'Good',
              'energy': 4,
              'symptoms': ['fatigue', 'headache'],
              'supportNeed': 'Hug',
              'privateNote': 'یادداشت خصوصی',
              'shareSummary': true,
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await api.updateWomenCalendarProfile(
      version: 3,
      enabled: true,
      lastPeriodStart: DateTime(2026, 8, 1),
      cycleLength: 28,
      periodLength: 5,
      remindersEnabled: true,
      includeDailyCheckIn: true,
      dailyCheckIn: {
        'date': '2026-08-05',
        'mood': 'good',
        'energy': 4,
        'symptoms': ['fatigue', 'headache'],
        'supportNeed': 'hug',
        'privateNote': 'یادداشت خصوصی',
        'shareSummary': true,
      },
    );

    expect(observed.method, 'PATCH');
    expect(observed.url.path, '/api/v1/women-calendar/profile');
    final payload = jsonDecode(observed.body) as Map<String, dynamic>;
    expect(payload['dailyCheckIn'], {
      'date': '2026-08-05',
      'mood': 'good',
      'energy': 4,
      'symptoms': ['fatigue', 'headache'],
      'supportNeed': 'hug',
      'privateNote': 'یادداشت خصوصی',
      'shareSummary': true,
    });
  });

  test('settings-only update omits the daily check-in key', () async {
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
