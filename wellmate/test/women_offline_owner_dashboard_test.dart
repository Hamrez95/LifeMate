import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

import '../lib/screens/women_calendar/women_offline_owner_dashboard.dart';

void main() {
  test('offline owner dashboard never reconstructs shared authorization state', () {
    final snapshot = WomenCalendarOfflineSnapshot(
      profile: const <String, dynamic>{
        'enabled': true,
        'lifecycleState': 'active',
        'lastPeriodStart': '2026-09-01',
      },
      episodes: const <Map<String, dynamic>>[
        <String, dynamic>{'startedOn': '2026-09-01'},
      ],
      lifecycleState: WomenHealthLifecycleState.active,
      storedAtUtc: DateTime.utc(2026, 9, 6, 1, 2, 3),
    );

    final value = WomenOfflineOwnerDashboard(
      snapshot: snapshot,
      dailyLogs: const <Map<String, dynamic>>[
        <String, dynamic>{
          'loggedOn': '2026-09-06',
          'version': 2,
          'mood': 'good',
          'energyLevel': 4,
          'painLevel': 2,
          'symptoms': <String>['cramps'],
          'privateNotes': 'owner-only',
          'shareSummaryWithCompanion': true,
          'relationshipId': 'must-not-survive',
          'consentId': 'must-not-survive',
        },
      ],
    ).toDashboardMap();

    expect(value['offlineCached'], isTrue);
    expect(value['offlineCachedAtUtc'], '2026-09-06T01:02:03.000Z');
    expect(value.containsKey('currentUser'), isFalse);
    expect(value.containsKey('currentProfile'), isFalse);
    expect(value.containsKey('relationships'), isFalse);

    final logs = (value['dailyLogs'] as List).cast<Map<String, dynamic>>();
    expect(logs, hasLength(1));
    expect(logs.single['mood'], 'good');
    expect(logs.single['energyLevel'], 4);
    expect(logs.single['privateNotes'], 'owner-only');
    expect(logs.single.containsKey('shareSummaryWithCompanion'), isFalse);
    expect(logs.single.containsKey('relationshipId'), isFalse);
    expect(logs.single.containsKey('consentId'), isFalse);
  });
}
