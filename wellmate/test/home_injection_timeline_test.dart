import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:wellmate/screens/home/home_schedule_loader.dart';

void main() {
  test('injection appears in aggregate daily timeline snapshot', () async {
    const loader = HomeScheduleLoader();
    final snapshot = await loader.load(
      api: _InjectionSnapshotApi(),
      fromDate: DateTime(2026, 8, 17),
      toDate: DateTime(2026, 8, 17),
    );

    expect(
      snapshot.careEvents.any(
        (event) => event['eventType'] == 'injection' && event['title'] == 'B12',
      ),
      isTrue,
    );
  });
}

class _InjectionSnapshotApi extends LifeMateApiClient {
  _InjectionSnapshotApi()
    : super(
        baseUri: Uri.parse('https://example.invalid'),
        accessToken: () => 'test-token',
      );

  @override
  Future<Map<String, dynamic>> getHomeSnapshot({
    required DateTime fromDate,
    required DateTime toDate,
  }) async => const {
    'currentUser': {
      'profile': {'displayName': 'ریحانه', 'timeZone': 'Asia/Tehran'},
    },
    'treatmentPlans': <Map<String, dynamic>>[],
    'doseOccurrences': <Map<String, dynamic>>[],
    'careEvents': [
      {
        'id': 'inj-1:2026-08-17',
        'seriesId': 'inj-1',
        'eventType': 'injection',
        'title': 'B12',
        'doseText': '۱ آمپول',
        'centerName': 'درمانگاه',
        'scheduledLocalDate': '2026-08-17',
        'scheduledLocalTime': '21:30',
        'status': 'scheduled',
      },
    ],
  };
}
