import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_core/lifemate_core.dart';

void main() {
  LifeMateDurableMutation upsert({
    required String id,
    required String date,
    required int version,
    required int pain,
    LifeMateMutationSyncState state = LifeMateMutationSyncState.pending,
    DateTime? createdAtUtc,
  }) => LifeMateDurableMutation(
    mutationId: id,
    domain: LifeMateMutationDomain.womenHealth,
    sourceKey: 'women-daily-log:$date',
    method: 'PUT',
    endpointPath: '/api/v1/women-calendar/daily-logs',
    payload: <String, dynamic>{
      'loggedOn': date,
      'version': version,
      'periodFlow': 'medium',
      'bloodAppearance': null,
      'bloodTexture': null,
      'painLevel': pain,
      'symptoms': <String>['cramps'],
      'privateNotes': null,
    },
    createdAtUtc: createdAtUtc ?? DateTime.utc(2026, 9, 5, 18),
    timeZone: 'Asia/Tehran',
    expectedRevision: version > 0 ? '$version' : null,
    state: state,
  );

  test(
    'pending owner write overlays canonical row without pretending confirmation',
    () {
      final result = LifeMateWomenDailyLogProjection.project(
        serverRows: const <Map<String, dynamic>>[
          <String, dynamic>{
            'loggedOn': '2026-09-05',
            'version': 3,
            'painLevel': 1,
          },
        ],
        pendingMutations: <LifeMateDurableMutation>[
          upsert(
            id: 'women-log-pending-0001',
            date: '2026-09-05',
            version: 3,
            pain: 4,
          ),
        ],
        fromDate: DateTime(2026, 9, 5),
        toDate: DateTime(2026, 9, 5),
      );

      expect(result.rows, hasLength(1));
      expect(result.rows.single['painLevel'], 4);
      expect(result.rows.single['pendingSync'], isTrue);
      expect(result.rows.single['serverConfirmed'], isFalse);
      expect(result.rows.single['localMutationId'], 'women-log-pending-0001');
      expect(result.pendingDates, {'2026-09-05'});
      expect(result.conflictDates, isEmpty);
    },
  );

  test('latest pending write wins local presentation deterministically', () {
    final result = LifeMateWomenDailyLogProjection.project(
      serverRows: const <Map<String, dynamic>>[],
      pendingMutations: <LifeMateDurableMutation>[
        upsert(
          id: 'women-log-pending-0001',
          date: '2026-09-05',
          version: 0,
          pain: 2,
          createdAtUtc: DateTime.utc(2026, 9, 5, 18),
        ),
        upsert(
          id: 'women-log-pending-0002',
          date: '2026-09-05',
          version: 0,
          pain: 5,
          createdAtUtc: DateTime.utc(2026, 9, 5, 19),
        ),
      ],
      fromDate: DateTime(2026, 9, 5),
      toDate: DateTime(2026, 9, 5),
    );

    expect(result.rows.single['painLevel'], 5);
    expect(result.rows.single['localMutationId'], 'women-log-pending-0002');
  });

  test('conflict never silently replaces canonical server row', () {
    final result = LifeMateWomenDailyLogProjection.project(
      serverRows: const <Map<String, dynamic>>[
        <String, dynamic>{
          'loggedOn': '2026-09-05',
          'version': 4,
          'painLevel': 1,
        },
      ],
      pendingMutations: <LifeMateDurableMutation>[
        upsert(
          id: 'women-log-conflict-0001',
          date: '2026-09-05',
          version: 3,
          pain: 5,
          state: LifeMateMutationSyncState.conflict,
        ),
      ],
      fromDate: DateTime(2026, 9, 5),
      toDate: DateTime(2026, 9, 5),
    );

    expect(result.rows.single['painLevel'], 1);
    expect(result.rows.single.containsKey('pendingSync'), isFalse);
    expect(result.conflictDates, {'2026-09-05'});
  });

  test('pending delete hides row but remains explicit pending local state', () {
    final delete = LifeMateOfflineWomenDailyLogMutation.buildDelete(
      mutationId: 'women-log-delete-0001',
      loggedOn: DateTime(2026, 9, 5),
      version: 4,
      timeZone: 'Asia/Tehran',
      createdAtUtc: DateTime.utc(2026, 9, 5, 19),
    );
    final result = LifeMateWomenDailyLogProjection.project(
      serverRows: const <Map<String, dynamic>>[
        <String, dynamic>{
          'loggedOn': '2026-09-05',
          'version': 4,
          'painLevel': 1,
        },
      ],
      pendingMutations: <LifeMateDurableMutation>[delete],
      fromDate: DateTime(2026, 9, 5),
      toDate: DateTime(2026, 9, 5),
    );

    expect(result.rows, isEmpty);
    expect(result.pendingDates, {'2026-09-05'});
    expect(result.pendingDeletedDates, {'2026-09-05'});
  });

  test('malformed matching mutation fails closed', () {
    final malformed = LifeMateDurableMutation(
      mutationId: 'women-log-malformed-0001',
      domain: LifeMateMutationDomain.womenHealth,
      sourceKey: 'women-daily-log:not-a-date',
      method: 'PUT',
      endpointPath: '/api/v1/women-calendar/daily-logs',
      payload: const <String, dynamic>{'loggedOn': 'not-a-date', 'version': 0},
      createdAtUtc: DateTime.utc(2026, 9, 5, 18),
      timeZone: 'Asia/Tehran',
    );

    expect(
      () => LifeMateWomenDailyLogProjection.project(
        serverRows: const <Map<String, dynamic>>[],
        pendingMutations: <LifeMateDurableMutation>[malformed],
        fromDate: DateTime(2026, 9, 5),
        toDate: DateTime(2026, 9, 5),
      ),
      throwsFormatException,
    );
  });
}
