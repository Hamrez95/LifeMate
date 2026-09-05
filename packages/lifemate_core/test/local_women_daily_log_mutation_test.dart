import 'package:lifemate_core/lifemate_core.dart';
import 'package:test/test.dart';

void main() {
  test('builds exact idempotent owner daily-log upsert', () {
    final mutation = LifeMateOfflineWomenDailyLogMutation.buildUpsert(
      mutationId: 'women-log-2026-09-05-0001',
      loggedOn: DateTime(2026, 9, 5),
      version: 3,
      timeZone: 'Asia/Tehran',
      periodFlow: 'medium',
      painLevel: 4,
      symptoms: const <String>{'headache', 'cramps'},
      privateNotes: ' owner note ',
      createdAtUtc: DateTime.utc(2026, 9, 5, 19),
    );

    expect(mutation.domain, LifeMateMutationDomain.womenHealth);
    expect(mutation.method, 'PUT');
    expect(mutation.endpointPath, '/api/v1/women-calendar/daily-logs');
    expect(mutation.sourceKey, 'women-daily-log:2026-09-05');
    expect(mutation.expectedRevision, '3');
    expect(mutation.timeZone, 'Asia/Tehran');
    expect(mutation.payload, <String, dynamic>{
      'loggedOn': '2026-09-05',
      'version': 3,
      'periodFlow': 'medium',
      'bloodAppearance': null,
      'bloodTexture': null,
      'painLevel': 4,
      'symptoms': <String>['cramps', 'headache'],
      'privateNotes': 'owner note',
    });
  });

  test('new daily log keeps revision unset while preserving version zero', () {
    final mutation = LifeMateOfflineWomenDailyLogMutation.buildUpsert(
      mutationId: 'women-log-2026-09-06-0001',
      loggedOn: DateTime(2026, 9, 6),
      version: 0,
      timeZone: 'Asia/Tehran',
      createdAtUtc: DateTime.utc(2026, 9, 5, 19),
    );

    expect(mutation.expectedRevision, isNull);
    expect(mutation.payload['version'], 0);
  });

  test('delete requires a known canonical revision', () {
    expect(
      () => LifeMateOfflineWomenDailyLogMutation.buildDelete(
        mutationId: 'women-log-delete-0001',
        loggedOn: DateTime(2026, 9, 5),
        version: 0,
        timeZone: 'Asia/Tehran',
      ),
      throwsArgumentError,
    );

    final mutation = LifeMateOfflineWomenDailyLogMutation.buildDelete(
      mutationId: 'women-log-delete-0002',
      loggedOn: DateTime(2026, 9, 5),
      version: 4,
      timeZone: 'Asia/Tehran',
      createdAtUtc: DateTime.utc(2026, 9, 5, 19),
    );
    expect(mutation.payload, <String, dynamic>{
      'loggedOn': '2026-09-05',
      'version': 4,
      'delete': true,
    });
    expect(mutation.expectedRevision, '4');
  });

  test('rejects malformed local inputs before persistence', () {
    expect(
      () => LifeMateOfflineWomenDailyLogMutation.buildUpsert(
        mutationId: 'short',
        loggedOn: DateTime(2026, 9, 5),
        version: 0,
        timeZone: 'Asia/Tehran',
      ),
      throwsArgumentError,
    );
    expect(
      () => LifeMateOfflineWomenDailyLogMutation.buildUpsert(
        mutationId: 'women-log-invalid-pain-0001',
        loggedOn: DateTime(2026, 9, 5),
        version: 0,
        timeZone: 'Asia/Tehran',
        painLevel: 6,
      ),
      throwsArgumentError,
    );
  });
}
