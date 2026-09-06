import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

import '../lib/screens/women_calendar/women_companion_dashboard_loader.dart';

void main() {
  final from = DateTime(2026, 6, 9);
  final to = DateTime(2026, 9, 6);

  test(
    'canonical dashboard is cached and remains authoritative online',
    () async {
      final offline = _FakeOfflinePort(
        cached: const <String, dynamic>{
          'profile': <String, dynamic>{'enabled': true},
        },
      );
      final canonical = <String, dynamic>{
        'profile': <String, dynamic>{
          'enabled': true,
          'lifecycleState': 'active',
        },
        'episodes': <Map<String, dynamic>>[
          <String, dynamic>{'startedOn': '2026-09-01'},
        ],
        'dailyLogs': <Map<String, dynamic>>[
          <String, dynamic>{'loggedOn': '2026-09-06', 'version': 2},
        ],
        'relationships': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'server-only'},
        ],
      };
      final loader = WomenCompanionDashboardLoader(
        fetchDashboard: ({required fromDate, required toDate}) async =>
            canonical,
        openOffline: () async => offline,
      );

      final result = await loader.load(fromDate: from, toDate: to);

      expect(result.offlineCached, isFalse);
      expect(result.dashboard, same(canonical));
      expect(offline.cacheCalls, 1);
      expect(offline.cachedProfile?['lifecycleState'], 'active');
      expect(offline.closed, isTrue);
    },
  );

  test(
    'transient transport failure falls back to owner-only cached map',
    () async {
      final offline = _FakeOfflinePort(
        cached: const <String, dynamic>{
          'profile': <String, dynamic>{
            'enabled': true,
            'lifecycleState': 'active',
          },
          'episodes': <Map<String, dynamic>>[],
          'dailyLogs': <Map<String, dynamic>>[],
          'offlineCached': true,
        },
      );
      final loader = WomenCompanionDashboardLoader(
        fetchDashboard: ({required fromDate, required toDate}) async {
          throw const LifeMateApiException(
            statusCode: 0,
            code: 'network_unavailable',
            message: 'offline',
          );
        },
        openOffline: () async => offline,
      );

      final result = await loader.load(fromDate: from, toDate: to);

      expect(result.offlineCached, isTrue);
      expect(result.dashboard['offlineCached'], isTrue);
      expect(result.dashboard.containsKey('relationships'), isFalse);
      expect(result.dashboard.containsKey('currentUser'), isFalse);
      expect(result.dashboard.containsKey('currentProfile'), isFalse);
      expect(offline.readCalls, 1);
      expect(offline.closed, isTrue);
    },
  );

  test(
    'protected cache read failure preserves the canonical transport error',
    () async {
      final offline = _FakeOfflinePort(cached: null, failRead: true);
      const canonicalError = LifeMateApiException(
        statusCode: 0,
        code: 'network_unavailable',
        message: 'offline',
      );
      final loader = WomenCompanionDashboardLoader(
        fetchDashboard: ({required fromDate, required toDate}) async {
          throw canonicalError;
        },
        openOffline: () async => offline,
      );

      await expectLater(
        loader.load(fromDate: from, toDate: to),
        throwsA(
          isA<LifeMateApiException>()
              .having((error) => error.code, 'code', canonicalError.code)
              .having(
                (error) => error.statusCode,
                'statusCode',
                canonicalError.statusCode,
              ),
        ),
      );
      expect(offline.readCalls, 1);
      expect(offline.closed, isTrue);
    },
  );

  for (final status in <int>[401, 403, 409]) {
    test('HTTP $status never falls back to stale owner cache', () async {
      final offline = _FakeOfflinePort(
        cached: const <String, dynamic>{
          'profile': <String, dynamic>{'enabled': true},
        },
      );
      final loader = WomenCompanionDashboardLoader(
        fetchDashboard: ({required fromDate, required toDate}) async {
          throw LifeMateApiException(
            statusCode: status,
            code: 'denied',
            message: 'denied',
          );
        },
        openOffline: () async => offline,
      );

      await expectLater(
        loader.load(fromDate: from, toDate: to),
        throwsA(isA<LifeMateApiException>()),
      );
      expect(offline.readCalls, 0);
      expect(offline.closed, isTrue);
    });
  }

  test('feature-disabled response never falls back', () async {
    final offline = _FakeOfflinePort(
      cached: const <String, dynamic>{
        'profile': <String, dynamic>{'enabled': true},
      },
    );
    final loader = WomenCompanionDashboardLoader(
      fetchDashboard: ({required fromDate, required toDate}) async {
        throw const LifeMateApiException(
          statusCode: 503,
          code: 'women_calendar_feature_disabled',
          message: 'disabled',
        );
      },
      openOffline: () async => offline,
    );

    await expectLater(
      loader.load(fromDate: from, toDate: to),
      throwsA(isA<LifeMateApiException>()),
    );
    expect(offline.readCalls, 0);
  });
}

final class _FakeOfflinePort implements WomenCompanionOfflineDashboardPort {
  _FakeOfflinePort({required this.cached, this.failRead = false});

  final Map<String, dynamic>? cached;
  final bool failRead;
  int cacheCalls = 0;
  int readCalls = 0;
  bool closed = false;
  Map<String, dynamic>? cachedProfile;

  @override
  Future<void> cacheOwnerDashboard({
    required Map<String, dynamic> profile,
    required Iterable<Map<String, dynamic>> episodes,
    required Iterable<Map<String, dynamic>> dailyLogs,
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    cacheCalls += 1;
    cachedProfile = profile;
  }

  @override
  Future<Map<String, dynamic>?> readOwnerDashboard({
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    readCalls += 1;
    if (failRead) throw StateError('protected cache unavailable');
    return cached;
  }

  @override
  void close() {
    closed = true;
  }
}
