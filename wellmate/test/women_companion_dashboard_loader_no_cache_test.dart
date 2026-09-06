import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

import '../lib/screens/women_calendar/women_companion_dashboard_loader.dart';

void main() {
  final from = DateTime(2026, 6, 9);
  final to = DateTime(2026, 9, 6);

  test('canonical dashboard remains usable when local cache is unavailable', () async {
    final canonical = <String, dynamic>{
      'profile': <String, dynamic>{'enabled': true},
      'episodes': <Map<String, dynamic>>[],
      'dailyLogs': <Map<String, dynamic>>[],
    };
    final loader = WomenCompanionDashboardLoader(
      fetchDashboard: ({required fromDate, required toDate}) async => canonical,
      openOffline: () async => null,
    );

    final result = await loader.load(fromDate: from, toDate: to);

    expect(result.dashboard, same(canonical));
    expect(result.offlineCached, isFalse);
  });

  test('transient API failure is not masked when local cache is unavailable', () async {
    const error = LifeMateApiException(
      statusCode: 0,
      code: 'network_unavailable',
      message: 'offline',
    );
    final loader = WomenCompanionDashboardLoader(
      fetchDashboard: ({required fromDate, required toDate}) async {
        throw error;
      },
      openOffline: () async => null,
    );

    await expectLater(
      loader.load(fromDate: from, toDate: to),
      throwsA(
        isA<LifeMateApiException>()
            .having((value) => value.code, 'code', error.code)
            .having((value) => value.statusCode, 'statusCode', error.statusCode),
      ),
    );
  });
}
