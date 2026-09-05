import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:lifemate_core/lifemate_core.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  final key = List<int>.generate(32, (index) => index + 1);

  test(
    'care-event projection remains readable offline only inside adopted Person namespace',
    () async {
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
      await ownerRuntime.applyCareEventPage(
        page: LifeMateProjectionPullPage(
          nextCursor: 'cursor-1',
          changes: <LifeMateServerProjectionChange>[
            LifeMateServerProjectionChange.upsert(
              recordKey: 'care-event-1',
              payload: <String, dynamic>{
                'id': 'care-event-1',
                'eventType': 'appointment',
                'scheduledAtUtc': '2026-09-06T08:00:00Z',
              },
              sourceRevision: '4',
            ),
          ],
        ),
      );

      final ownerRecords = await ownerRuntime.careEventProjections();
      expect(ownerRecords, hasLength(1));
      expect(ownerRecords.single.recordKey, 'care-event-1');
      expect(ownerRecords.single.sourceRevision, '4');
      expect(ownerRecords.single.payload['eventType'], 'appointment');

      final otherPersonRuntime = await openRuntime('person-b');
      addTearDown(otherPersonRuntime.close);
      expect(await otherPersonRuntime.careEventProjections(), isEmpty);
    },
  );
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
