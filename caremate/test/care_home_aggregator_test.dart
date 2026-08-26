import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

import 'package:caremate/models/care_home_snapshot.dart';
import 'package:caremate/services/care_home_aggregator.dart';

void main() {
  final now = DateTime(2026, 8, 9, 8);

  test('global queue orders recipients only by scheduled time', () {
    final snapshot = CareHomeAggregator.buildSnapshot(
      currentUser: const {},
      relationships: const [
        CareHomeRelationship(
          relationshipId: 'rel-r',
          patientUserId: 'reihana',
          patientDisplayName: 'ریحانه',
          canViewWomenCalendar: false,
        ),
        CareHomeRelationship(
          relationshipId: 'rel-m',
          patientUserId: 'mother',
          patientDisplayName: 'مادر',
          canViewWomenCalendar: false,
        ),
      ],
      dosesByPatient: {
        'reihana': [_dose('dose-r', hour: 10, medication: 'ویتامین D')],
      },
      eventsByPatient: {
        'mother': [_event('inj-m', hour: 9, type: 'injection', title: 'آمپول B12')],
      },
      companion: CareCompanionHomeSummary.locked(),
      now: now,
    );

    expect(snapshot.currentTreatment?.patientDisplayName, 'مادر');
    expect(snapshot.currentTreatment?.type, CareItemType.injection);
    expect(snapshot.nextTreatment?.patientDisplayName, 'ریحانه');
    expect(snapshot.nextTreatment?.type, CareItemType.medication);
  });

  test('current and next may both belong to the same recipient', () {
    final relationship = _relationship('rel-r', 'reihana', 'ریحانه');
    final snapshot = CareHomeAggregator.buildSnapshot(
      currentUser: const {},
      relationships: [relationship],
      dosesByPatient: {
        'reihana': [
          _dose('dose-1', hour: 9, medication: 'داروی اول'),
          _dose('dose-2', hour: 10, medication: 'داروی دوم'),
        ],
      },
      eventsByPatient: const {},
      companion: CareCompanionHomeSummary.locked(),
      now: now,
    );

    expect(snapshot.currentTreatment?.patientUserId, 'reihana');
    expect(snapshot.nextTreatment?.patientUserId, 'reihana');
  });

  test('medication visit and injection are normalized into one queue', () {
    final relationship = _relationship('rel-r', 'reihana', 'ریحانه');
    final snapshot = CareHomeAggregator.buildSnapshot(
      currentUser: const {},
      relationships: [relationship],
      dosesByPatient: {'reihana': [_dose('dose', hour: 9)]},
      eventsByPatient: {
        'reihana': [
          _event('visit', hour: 10, type: 'appointment', title: 'ویزیت قلب'),
          _event('inj', hour: 11, type: 'injection', title: 'تزریق'),
        ],
      },
      companion: CareCompanionHomeSummary.locked(),
      now: now,
    );

    expect(
      snapshot.queueItems.map((item) => item.type),
      [CareItemType.medication, CareItemType.visit, CareItemType.injection],
    );
  });

  test('queue is sorted by scheduledAt and cancelled items are excluded', () {
    final relationship = _relationship('rel-r', 'reihana', 'ریحانه');
    final snapshot = CareHomeAggregator.buildSnapshot(
      currentUser: const {},
      relationships: [relationship],
      dosesByPatient: {
        'reihana': [
          _dose('late', hour: 18),
          _dose('cancelled', hour: 8, status: 'cancelled'),
          _dose('early', hour: 9),
        ],
      },
      eventsByPatient: const {},
      companion: CareCompanionHomeSummary.locked(),
      now: now,
    );

    expect(snapshot.queueItems.map((item) => item.occurrenceId), ['early', 'late']);
  });

  test('single and empty queues expose stable current/next states', () {
    final relationship = _relationship('rel-r', 'reihana', 'ریحانه');
    final one = CareHomeAggregator.buildSnapshot(
      currentUser: const {},
      relationships: [relationship],
      dosesByPatient: {'reihana': [_dose('only', hour: 10)]},
      eventsByPatient: const {},
      companion: CareCompanionHomeSummary.locked(),
      now: now,
    );
    final empty = CareHomeAggregator.buildSnapshot(
      currentUser: const {},
      relationships: [relationship],
      dosesByPatient: const {},
      eventsByPatient: const {},
      companion: CareCompanionHomeSummary.locked(),
      now: now,
    );

    expect(one.currentTreatment?.occurrenceId, 'only');
    expect(one.nextTreatment, isNull);
    expect(empty.currentTreatment, isNull);
    expect(empty.nextTreatment, isNull);
  });

  test('profile photo and avatar fallback metadata survive normalization', () {
    const relationship = CareHomeRelationship(
      relationshipId: 'rel-r',
      patientUserId: 'reihana',
      patientDisplayName: 'ریحانه',
      patientProfilePhotoUrl: 'https://signed.example/photo',
      patientAvatarKey: 'person_purple',
      canViewWomenCalendar: false,
    );
    final snapshot = CareHomeAggregator.buildSnapshot(
      currentUser: const {},
      relationships: const [relationship],
      dosesByPatient: {'reihana': [_dose('dose', hour: 9)]},
      eventsByPatient: const {},
      companion: CareCompanionHomeSummary.locked(),
      now: now,
    );

    expect(snapshot.currentTreatment?.patientProfilePhotoUrl, 'https://signed.example/photo');
    expect(snapshot.currentTreatment?.patientAvatarKey, 'person_purple');
  });

  test('server exact scope can authorize even when legacy flag is false', () async {
    final api = _PermissionAwareApi(
      legacyCanViewWomenCalendar: false,
      serverAllowsCompanion: true,
    );
    final snapshot = await CareHomeAggregator(api).load(now: now);

    expect(api.companionCalls, 1);
    expect(snapshot.companion.hasPermission, isTrue);
    expect(snapshot.companion.phaseAllowed, isTrue);
    expect(snapshot.companion.wellbeingAllowed, isTrue);
    expect(snapshot.companion.cycleDay, 12);
    expect(snapshot.companion.mood, 'good');
    expect(snapshot.companion.energyLevel, 4);
  });

  test('server revoke is fail-closed regardless of stale legacy flag', () async {
    final api = _PermissionAwareApi(
      legacyCanViewWomenCalendar: true,
      serverAllowsCompanion: false,
    );
    final snapshot = await CareHomeAggregator(api).load(now: now);

    expect(api.companionCalls, 1);
    expect(snapshot.companion.hasPermission, isFalse);
    expect(snapshot.companion.available, isFalse);
    expect(snapshot.companion.cycleDay, isNull);
    expect(snapshot.companion.mood, isNull);
  });

  test('private fields from an unexpected payload never enter companion model', () async {
    final api = _PermissionAwareApi(
      legacyCanViewWomenCalendar: false,
      serverAllowsCompanion: true,
    );
    final snapshot = await CareHomeAggregator(api).load(now: now);

    expect(snapshot.companion.mood, 'good');
    expect(snapshot.companion.energyLevel, 4);
    expect(snapshot.companion.guidanceHistory.single.guidanceId, 'general.ask_first');
  });

  test('today plan aggregates multiple recipients and all treatment types', () {
    final reihana = _relationship('rel-r', 'reihana', 'ریحانه');
    final mother = _relationship('rel-m', 'mother', 'مادر');
    final snapshot = CareHomeAggregator.buildSnapshot(
      currentUser: const {},
      relationships: [reihana, mother],
      dosesByPatient: {'reihana': [_dose('med', hour: 9, status: 'taken')]},
      eventsByPatient: {
        'mother': [
          _event('visit', hour: 10, type: 'appointment', title: 'ویزیت'),
          _event('inj', hour: 11, type: 'injection', title: 'تزریق'),
        ],
      },
      companion: CareCompanionHomeSummary.locked(),
      now: now,
    );

    expect(snapshot.todayItems.length, 3);
    expect(snapshot.todayItems.map((item) => item.patientUserId).toSet(), {'reihana', 'mother'});
    expect(snapshot.todayItems.map((item) => item.type).toSet(), {
      CareItemType.medication,
      CareItemType.visit,
      CareItemType.injection,
    });
    expect(snapshot.completedToday, 1);
  });
}

CareHomeRelationship _relationship(String id, String patientId, String name) =>
    CareHomeRelationship(
      relationshipId: id,
      patientUserId: patientId,
      patientDisplayName: name,
      canViewWomenCalendar: false,
    );

Map<String, dynamic> _dose(
  String id, {
  required int hour,
  String status = 'scheduled',
  String medication = 'دارو',
}) => {
  'id': id,
  'treatmentPlanId': 'plan-$id',
  'medicationName': medication,
  'doseText': 'یک عدد',
  'scheduledLocalDate': '2026-08-09',
  'scheduledLocalTime': '${hour.toString().padLeft(2, '0')}:00',
  'status': status,
};

Map<String, dynamic> _event(
  String id, {
  required int hour,
  required String type,
  required String title,
  String status = 'scheduled',
}) => {
  'id': id,
  'seriesId': 'series-$id',
  'eventType': type,
  'title': title,
  if (type == 'injection') 'medicationName': 'B12',
  'scheduledLocalDate': '2026-08-09',
  'scheduledLocalTime': '${hour.toString().padLeft(2, '0')}:00',
  'status': status,
};

class _PermissionAwareApi extends LifeMateApiClient {
  _PermissionAwareApi({
    required this.legacyCanViewWomenCalendar,
    required this.serverAllowsCompanion,
  }) : super(
         baseUri: Uri.parse('https://example.invalid'),
         accessToken: () => 'token',
       );

  final bool legacyCanViewWomenCalendar;
  final bool serverAllowsCompanion;
  int companionCalls = 0;

  @override
  Future<Map<String, dynamic>> getCurrentUser() async => const {
    'user': {'id': 'caregiver'},
    'profile': {'timeZone': 'Asia/Tehran'},
  };

  @override
  Future<List<Map<String, dynamic>>> getCareRelationships() async => [
    {
      'id': 'rel-1',
      'patientUserId': 'patient',
      'patientDisplayName': 'ریحانه',
      'patientAvatarKey': 'person_purple',
      'caregiverUserId': 'caregiver',
      'status': 'active',
      'canViewWomenCalendar': legacyCanViewWomenCalendar,
    },
  ];

  @override
  Future<List<Map<String, dynamic>>> getCareRecipientDoseOccurrences({
    required String patientUserId,
    required DateTime fromDate,
    required DateTime toDate,
  }) async => const [];

  @override
  Future<List<Map<String, dynamic>>> getCareRecipientCareEvents({
    required String patientUserId,
    required DateTime fromDate,
    required DateTime toDate,
  }) async => const [];

  @override
  Future<Map<String, dynamic>> getCareRecipientWomenCalendar({
    required String patientUserId,
  }) async {
    companionCalls += 1;
    if (!serverAllowsCompanion) {
      throw const LifeMateApiException(
        statusCode: 403,
        code: 'women_calendar_access_denied',
        message: 'revoked',
      );
    }
    return {
      'privacyScopes': {
        'viewPhaseSummary': true,
        'viewSharedWellbeing': true,
      },
      'estimate': {'cycleDay': 12, 'cycleLength': 28},
      'latestSharedDailyLog': {
        'mood': 'good',
        'energyLevel': 4,
        'privateNotes': 'MUST-NOT-BE-USED',
        'painLevel': 5,
        'symptoms': ['MUST-NOT-BE-USED'],
      },
      'supportActions': const [],
      'guidanceHistory': [
        {
          'guidanceId': 'general.ask_first',
          'contentVersion': 'companion-care-v1',
          'category': 'general',
          'shownAtUtc': DateTime.utc(2026, 8, 1).toIso8601String(),
        },
      ],
    };
  }
}
