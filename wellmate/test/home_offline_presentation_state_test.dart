import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:wellmate/screens/home/home_schedule_loader.dart';

void main() {
  const loader = HomeScheduleLoader();
  final fromDate = DateTime(2026, 9, 5);
  final toDate = DateTime(2026, 9, 12);

  tearDown(() {
    homeOfflinePresentationState.value = const HomeOfflinePresentationState();
  });

  test('cached snapshot publishes local presentation state and freshness', () async {
    await loader.load(
      api: _PresentationApi(cached: true),
      fromDate: fromDate,
      toDate: toDate,
    );

    expect(homeOfflinePresentationState.value.cached, isTrue);
    expect(
      homeOfflinePresentationState.value.cachedAtUtc,
      DateTime.utc(2026, 9, 5, 6, 30),
    );
  });

  test('fresh server snapshot clears a previously cached presentation state', () async {
    homeOfflinePresentationState.value = HomeOfflinePresentationState(
      cached: true,
      cachedAtUtc: DateTime.utc(2026, 9, 5, 6),
    );

    await loader.load(
      api: _PresentationApi(),
      fromDate: fromDate,
      toDate: toDate,
    );

    expect(homeOfflinePresentationState.value.cached, isFalse);
    expect(homeOfflinePresentationState.value.cachedAtUtc, isNull);
  });

  test('non-fallback auth failure clears stale cached presentation state', () async {
    homeOfflinePresentationState.value = const HomeOfflinePresentationState(
      cached: true,
    );

    await expectLater(
      loader.load(
        api: _PresentationApi(failUnauthorized: true),
        fromDate: fromDate,
        toDate: toDate,
      ),
      throwsA(
        isA<LifeMateApiException>().having(
          (value) => value.statusCode,
          'statusCode',
          401,
        ),
      ),
    );

    expect(homeOfflinePresentationState.value.cached, isFalse);
  });
}

class _PresentationApi extends LifeMateApiClient {
  _PresentationApi({this.cached = false, this.failUnauthorized = false})
    : super(
        baseUri: Uri.parse('https://example.invalid'),
        accessToken: () => 'test-token',
      );

  final bool cached;
  final bool failUnauthorized;

  @override
  Future<Map<String, dynamic>> getHomeSnapshot({
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    if (failUnauthorized) {
      throw const LifeMateApiException(
        statusCode: 401,
        code: 'unauthorized',
        message: 'Session expired.',
      );
    }
    return <String, dynamic>{
      'currentUser': const <String, dynamic>{
        'profile': <String, dynamic>{'timeZone': 'Asia/Tehran'},
      },
      'treatmentPlans': const <Map<String, dynamic>>[],
      'doseOccurrences': const <Map<String, dynamic>>[],
      'careEvents': const <Map<String, dynamic>>[],
      'offlineCached': cached,
      if (cached) 'offlineCachedAtUtc': '2026-09-05T06:30:00Z',
    };
  }
}
