import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:wellmate/screens/home/home_schedule_loader.dart';

void main() {
  const loader = HomeScheduleLoader();
  final fromDate = DateTime(2026, 8, 6);
  final toDate = DateTime(2026, 8, 13);

  test('cached Home snapshot exposes explicit offline freshness state', () async {
    final snapshot = await loader.load(
      api: _CachedHomeApi(),
      fromDate: fromDate,
      toDate: toDate,
    );

    expect(snapshot.offlineCached, isTrue);
    expect(snapshot.offlineCachedAtUtc, DateTime.utc(2026, 8, 6, 8, 30));
    expect(snapshot.doseOccurrences.single['id'], 'dose-cached');
    expect(snapshot.failures, isEmpty);
  });

  test('care-events failure does not hide a valid medicine schedule', () async {
    final snapshot = await loader.load(
      api: _FakeHomeApi(failCareEvents: true),
      fromDate: fromDate,
      toDate: toDate,
    );

    expect(snapshot.doseOccurrences, hasLength(1));
    expect(snapshot.careEvents, isEmpty);
    expect(snapshot.isPartial, isTrue);
    expect(snapshot.offlineCached, isFalse);
    expect(snapshot.failures.single.source, 'care-events');
  });

  test('dose failure does not hide a valid appointment schedule', () async {
    final snapshot = await loader.load(
      api: _FakeHomeApi(failDoses: true),
      fromDate: fromDate,
      toDate: toDate,
    );

    expect(snapshot.doseOccurrences, isEmpty);
    expect(snapshot.careEvents, hasLength(1));
    expect(snapshot.isPartial, isTrue);
    expect(snapshot.failures.single.source, 'dose-occurrences');
  });

  test('treatment-plan failure keeps raw occurrences visible', () async {
    final snapshot = await loader.load(
      api: _FakeHomeApi(failPlans: true),
      fromDate: fromDate,
      toDate: toDate,
    );

    expect(snapshot.doseOccurrences, hasLength(1));
    expect(snapshot.careEvents, hasLength(1));
    expect(snapshot.treatmentPlans, isEmpty);
    expect(snapshot.failures.single.source, 'treatment-plans');
  });

  test('home fails only when both schedule sources fail', () async {
    await expectLater(
      loader.load(
        api: _FakeHomeApi(failDoses: true, failCareEvents: true),
        fromDate: fromDate,
        toDate: toDate,
      ),
      throwsA(
        isA<HomeScheduleLoadException>().having(
          (value) => value.failures.map((failure) => failure.source).toSet(),
          'failed sources',
          {'dose-occurrences', 'care-events'},
        ),
      ),
    );
  });

  test('identity failure is never presented as an empty schedule', () async {
    await expectLater(
      loader.load(
        api: _FakeHomeApi(failCurrentUser: true),
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
  });
}

class _CachedHomeApi extends LifeMateApiClient {
  _CachedHomeApi()
    : super(
        baseUri: Uri.parse('https://example.invalid'),
        accessToken: () => 'test-token',
      );

  @override
  Future<Map<String, dynamic>> getHomeSnapshot({
    required DateTime fromDate,
    required DateTime toDate,
  }) async => const <String, dynamic>{
    'currentUser': <String, dynamic>{
      'profile': <String, dynamic>{'timeZone': 'Asia/Tehran'},
    },
    'treatmentPlans': <Map<String, dynamic>>[],
    'doseOccurrences': <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'dose-cached',
        'scheduledLocalDate': '2026-08-06',
      },
    ],
    'careEvents': <Map<String, dynamic>>[],
    'offlineCached': true,
    'offlineCachedAtUtc': '2026-08-06T08:30:00Z',
  };
}

class _FakeHomeApi extends LifeMateApiClient {
  _FakeHomeApi({
    this.failCurrentUser = false,
    this.failPlans = false,
    this.failDoses = false,
    this.failCareEvents = false,
  }) : super(
         baseUri: Uri.parse('https://example.invalid'),
         accessToken: () => 'test-token',
       );

  final bool failCurrentUser;
  final bool failPlans;
  final bool failDoses;
  final bool failCareEvents;

  @override
  Future<Map<String, dynamic>> getHomeSnapshot({
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    throw const LifeMateApiException(
      statusCode: 404,
      code: 'route_not_found',
      message: 'Exercise the legacy partial-response fallback.',
    );
  }

  @override
  Future<Map<String, dynamic>> getCurrentUser() async {
    if (failCurrentUser) {
      throw const LifeMateApiException(
        statusCode: 401,
        code: 'unauthorized',
        message: 'Session expired.',
      );
    }
    return const {
      'profile': {'displayName': 'حمیدرضا', 'timeZone': 'Asia/Tehran'},
    };
  }

  @override
  Future<List<Map<String, dynamic>>> getTreatmentPlans() async {
    if (failPlans) {
      throw const LifeMateApiException(
        statusCode: 503,
        code: 'temporarily_unavailable',
        message: 'Plans unavailable.',
      );
    }
    return const [
      {
        'id': 'plan-1',
        'doseText': '۱ قرص',
        'medication': {'name': 'آسپرین'},
      },
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> getDoseOccurrences({
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    if (failDoses) {
      throw const LifeMateApiException(
        statusCode: 503,
        code: 'temporarily_unavailable',
        message: 'Doses unavailable.',
      );
    }
    return const [
      {
        'id': 'dose-1',
        'treatmentPlanId': 'plan-1',
        'scheduledLocalDate': '2026-08-06',
        'scheduledLocalTime': '08:00:00',
        'status': 'scheduled',
        'version': 1,
      },
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> getCareEvents({
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    if (failCareEvents) {
      throw const LifeMateApiException(
        statusCode: 404,
        code: 'route_not_found',
        message: 'Care-events route not deployed.',
      );
    }
    return const [
      {
        'id': 'event-1',
        'eventType': 'appointment',
        'title': 'ویزیت پزشک',
        'scheduledLocalDate': '2026-08-06',
        'scheduledLocalTime': '12:00:00',
        'status': 'scheduled',
        'version': 1,
      },
    ];
  }
}
