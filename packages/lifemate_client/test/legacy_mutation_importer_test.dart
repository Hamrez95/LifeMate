import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:lifemate_core/lifemate_core.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  final key = List<int>.generate(32, (index) => index + 1);
  final namespace = LifeMateLocalNamespace(
    environmentId: 'test',
    accountId: 'account-a',
    personId: 'person-a',
  );

  test('imports dose mutation before deleting legacy copy', () async {
    final storage = _MemoryStorage();
    final legacy = LifeMateOfflineMutationQueue(
      storage: storage,
      now: () => DateTime.utc(2026, 9, 5, 1),
    );
    const requestId = '123e4567-e89b-42d3-a456-426614174901';
    const occurrenceId = '123e4567-e89b-42d3-a456-426614174010';
    await legacy.enqueue(
      accountId: 'account-a',
      method: 'POST',
      uri: Uri.parse(
        'https://api.example.test/api/v1/dose-occurrences/$occurrenceId/report',
      ),
      body: jsonEncode(<String, dynamic>{
        'clientRequestId': requestId,
        'status': 'taken',
        'expectedVersion': 7,
      }),
      clientRequestId: requestId,
    );

    final database = sqlite3.openInMemory();
    final store = LifeMateLocalHealthStore.forTesting(
      database: database,
      keyBytes: key,
    );
    final outbox = LifeMateLocalMutationOutbox(store: store);
    final importer = LifeMateLegacyMutationImporter(
      legacyStorage: storage,
      outbox: outbox,
      apiBaseUri: Uri.parse('https://api.example.test'),
    );

    expect(
      await importer.importPending(
        namespace: namespace,
        timeZone: 'Asia/Tehran',
      ),
      1,
    );
    expect(await legacy.pendingForAccount('account-a'), isEmpty);
    final structured = await outbox.list(namespace: namespace);
    expect(structured, hasLength(1));
    expect(structured.single.mutationId, requestId);
    expect(structured.single.domain, LifeMateMutationDomain.adherence);
    expect(structured.single.sourceKey, occurrenceId);
    expect(structured.single.expectedRevision, '7');
    expect(structured.single.payload['status'], 'taken');
    store.close();
  });

  test(
    'does not delete legacy mutation when structured persistence fails',
    () async {
      final storage = _MemoryStorage();
      final legacy = LifeMateOfflineMutationQueue(storage: storage);
      const requestId = '123e4567-e89b-42d3-a456-426614174902';
      const occurrenceId = '123e4567-e89b-42d3-a456-426614174011';
      await legacy.enqueue(
        accountId: 'account-a',
        method: 'POST',
        uri: Uri.parse(
          'https://api.example.test/api/v1/dose-occurrences/$occurrenceId/report',
        ),
        body: jsonEncode(<String, dynamic>{
          'clientRequestId': requestId,
          'status': 'skipped',
        }),
        clientRequestId: requestId,
      );

      final database = sqlite3.openInMemory();
      final store = LifeMateLocalHealthStore.forTesting(
        database: database,
        keyBytes: key,
      );
      final outbox = LifeMateLocalMutationOutbox(
        store: store,
        maximumItemsPerPerson: 1,
      );
      await outbox.enqueue(
        namespace: namespace,
        mutation: LifeMateDurableMutation(
          mutationId: 'already-full',
          domain: LifeMateMutationDomain.adherence,
          sourceKey: 'existing',
          method: 'POST',
          endpointPath: '/api/v1/dose-occurrences/existing/report',
          payload: const <String, dynamic>{'clientRequestId': 'already-full'},
          createdAtUtc: DateTime.utc(2026, 9, 5),
          timeZone: 'UTC',
        ),
      );
      final importer = LifeMateLegacyMutationImporter(
        legacyStorage: storage,
        outbox: outbox,
        apiBaseUri: Uri.parse('https://api.example.test'),
      );

      await expectLater(
        importer.importPending(namespace: namespace, timeZone: 'Asia/Tehran'),
        throwsStateError,
      );
      expect(await legacy.pendingForAccount('account-a'), hasLength(1));
      store.close();
    },
  );

  test(
    'imports records older than the legacy seven-day TTL without pruning',
    () async {
      final storage = _MemoryStorage();
      final old = LifeMateQueuedMutation(
        id: 'account-a:123e4567-e89b-42d3-a456-426614174904',
        accountId: 'account-a',
        method: 'POST',
        uri:
            'https://api.example.test/api/v1/dose-occurrences/123e4567-e89b-42d3-a456-426614174013/report',
        body: jsonEncode(<String, dynamic>{
          'clientRequestId': '123e4567-e89b-42d3-a456-426614174904',
          'status': 'taken',
        }),
        clientRequestId: '123e4567-e89b-42d3-a456-426614174904',
        createdAtUtc: DateTime.utc(2026, 8, 1),
      );
      await storage.write(
        'lifemate.offline_mutation.v2.expired-but-accepted',
        jsonEncode(old.toJson()),
      );

      final database = sqlite3.openInMemory();
      final store = LifeMateLocalHealthStore.forTesting(
        database: database,
        keyBytes: key,
      );
      final outbox = LifeMateLocalMutationOutbox(store: store);
      final importer = LifeMateLegacyMutationImporter(
        legacyStorage: storage,
        outbox: outbox,
        apiBaseUri: Uri.parse('https://api.example.test'),
      );

      expect(
        await importer.importPending(
          namespace: namespace,
          timeZone: 'Asia/Tehran',
        ),
        1,
      );
      expect(storage.values, isEmpty);
      expect(await outbox.list(namespace: namespace), hasLength(1));
      store.close();
    },
  );

  test(
    'retains unsafe origin and malformed legacy records for explicit handling',
    () async {
      final storage = _MemoryStorage();
      final legacy = LifeMateOfflineMutationQueue(storage: storage);
      const requestId = '123e4567-e89b-42d3-a456-426614174903';
      const occurrenceId = '123e4567-e89b-42d3-a456-426614174012';
      await legacy.enqueue(
        accountId: 'account-a',
        method: 'POST',
        uri: Uri.parse(
          'https://old-api.example.test/api/v1/dose-occurrences/$occurrenceId/report',
        ),
        body: jsonEncode(<String, dynamic>{'clientRequestId': requestId}),
        clientRequestId: requestId,
      );
      await storage.write(
        'lifemate.offline_mutation.v2.malformed',
        '{bad-json',
      );

      final database = sqlite3.openInMemory();
      final store = LifeMateLocalHealthStore.forTesting(
        database: database,
        keyBytes: key,
      );
      final importer = LifeMateLegacyMutationImporter(
        legacyStorage: storage,
        outbox: LifeMateLocalMutationOutbox(store: store),
        apiBaseUri: Uri.parse('https://api.example.test'),
      );

      expect(
        await importer.importPending(namespace: namespace, timeZone: 'UTC'),
        0,
      );
      expect(storage.values, hasLength(2));
      store.close();
    },
  );
}

final class _MemoryStorage implements LifeMateMutationStorage {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<Map<String, String>> readAll() async =>
      Map<String, String>.from(values);

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}
