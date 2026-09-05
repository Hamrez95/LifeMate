import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:lifemate_core/lifemate_core.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  final key = List<int>.generate(32, (index) => index + 1);

  test('treatment plan and occurrence projections stay durable and isolated', () async {
    final database = sqlite3.openInMemory();
    final store = LifeMateLocalHealthStore.forTesting(
      database: database,
      keyBytes: key,
    );
    addTearDown(store.close);
    final legacyStorage = _MemoryMutationStorage();

    Future<LifeMateSharedOfflineRuntime> openRuntime(String personId) =>
        LifeMateSharedOfflineRuntime.open(
          namespace: LifeMateOfflineNamespace(
            environmentId: 'test-environment',
            accountId: 'account-a',
            personId: personId,
          ),
          timeZone: 'Asia/Tehran',
          apiBaseUri: Uri.parse('https://api.example.test'),
          accessToken: () => 'test-token',
          store: store,
          legacyStorage: legacyStorage,
        );

    final ownerRuntime = await openRuntime('person-a');
    addTearDown(ownerRuntime.close);

    await ownerRuntime.applyTreatmentPlanPage(
      page: LifeMateProjectionPullPage(
        nextCursor: 'plan-cursor-1',
        sourceRevision: 'plan-set-7',
        changes: <LifeMateServerProjectionChange>[
          LifeMateServerProjectionChange.upsert(
            recordKey: 'plan-1',
            payload: <String, dynamic>{'id': 'plan-1', 'title': 'Vitamin D'},
            sourceRevision: '7',
          ),
        ],
      ),
    );
    await ownerRuntime.applyTreatmentOccurrencePage(
      page: LifeMateProjectionPullPage(
        nextCursor: 'occurrence-cursor-1',
        changes: <LifeMateServerProjectionChange>[
          LifeMateServerProjectionChange.upsert(
            recordKey: 'dose-1',
            payload: <String, dynamic>{
              'id': 'dose-1',
              'treatmentPlanId': 'plan-1',
              'scheduledAtUtc': '2026-09-05T05:00:00Z',
            },
            sourceRevision: '11',
          ),
        ],
      ),
    );

    final plans = await ownerRuntime.treatmentPlanProjections();
    final occurrences = await ownerRuntime.treatmentOccurrenceProjections();
    expect(plans.single.recordKey, 'plan-1');
    expect(plans.single.payload['title'], 'Vitamin D');
    expect(occurrences.single.recordKey, 'dose-1');
    expect(occurrences.single.payload['treatmentPlanId'], 'plan-1');
    expect((await ownerRuntime.treatmentPlanCheckpoint())?.cursor, 'plan-cursor-1');
    expect(
      (await ownerRuntime.treatmentOccurrenceCheckpoint())?.cursor,
      'occurrence-cursor-1',
    );

    final otherPersonRuntime = await openRuntime('person-b');
    addTearDown(otherPersonRuntime.close);
    expect(await otherPersonRuntime.treatmentPlanProjections(), isEmpty);
    expect(await otherPersonRuntime.treatmentOccurrenceProjections(), isEmpty);
    expect(await otherPersonRuntime.treatmentPlanCheckpoint(), isNull);
    expect(await otherPersonRuntime.treatmentOccurrenceCheckpoint(), isNull);
  });
}

final class _MemoryMutationStorage implements LifeMateMutationStorage {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<Map<String, String>> readAll() async =>
      Map<String, String>.unmodifiable(_values);

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }
}
