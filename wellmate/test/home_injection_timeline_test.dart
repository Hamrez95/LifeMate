import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:wellmate/models/schedule_item_model.dart';
import 'package:wellmate/screens/home/home_schedule_loader.dart';
import 'package:wellmate/screens/home/home_screen_content.dart';

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

  test('countdown stays single and injection is eligible when it is next', () {
    final date = DateTime(2026, 8, 17);
    final items = [
      ScheduleItemModel(
        id: 'visit-1',
        title: 'چکاپ',
        time: '18:30',
        dosage: '',
        type: 'appointment',
        frequency: 'ویزیت',
        startDate: date,
      ),
      ScheduleItemModel(
        id: 'dose-1',
        title: 'دارو',
        time: '21:00',
        dosage: '۱ عدد',
        type: 'medicine',
        frequency: 'طبق برنامه',
        startDate: date,
      ),
      ScheduleItemModel(
        id: 'inj-1',
        title: 'B12',
        time: '21:30',
        dosage: '۱ آمپول',
        type: 'injection',
        frequency: 'تزریق',
        startDate: date,
      ),
    ];

    final first = selectHomeCountdownItems(items, DateTime(2026, 8, 17, 17));
    expect(first.map((item) => item.id), ['visit-1']);

    final injectionNext = selectHomeCountdownItems([
      items[0].copyWith(status: 'completed', isDone: true),
      items[1].copyWith(status: 'taken', isDone: true),
      items[2],
    ], DateTime(2026, 8, 17, 19));
    expect(injectionNext.map((item) => item.id), ['inj-1']);
  });

  test('home countdown UI is fixed rather than a carousel', () {
    final source = File(
      'lib/screens/home/home_screen_content.dart',
    ).readAsStringSync();
    expect(source, isNot(contains('home-countdown-carousel')));
    expect(source, contains('item: countdownItems.first'));
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
