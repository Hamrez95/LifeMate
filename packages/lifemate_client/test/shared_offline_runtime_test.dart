import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lifemate_client/lifemate_client.dart';
import 'package:lifemate_core/lifemate_core.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  final key = List<int>.generate(32, (index) => index + 1);
  final namespace = LifeMateLocalNamespace(
    environmentId: 'production',
    accountId: 'account-a',
    personId: 'person-a',
  );

  test('initialization migrates legacy action before bounded replay', () async {
    final storage = _MemoryStorage();
    final legacy = LifeMateOfflineMutationQueue(storage: storage);
    const requestId = '123e4567-e89b-42d3-a456-426614174951';
    const occurrenceId = '123e4567-e89b-42d3-a456-426614174051';
    await legacy.enqueue(
      accountId: 'account-a',
      method: 'POST',
      uri: Uri.parse(
        'https://api.example.test/api/v1/dose-occurrences/$occurrenceId/report',
      ),
      body: jsonEncode(<String, dynamic>{
        'clientRequestId': requestId,
        'status': 'taken',
        'expectedVersion': 2,
      }),
      clientRequestId: requestId,
    );

    final database = sqlite3.openInMemory();
    final store = LifeMateLocalHealthStore.forTesting(
      database: database,
      keyBytes: key,
    );
    final client = _RecordingClient(statusCodes: <int>[200]);
    final runtime = await LifeMateSharedOfflineRuntime.open(
      namespace: namespace,
      timeZone: 'Asia/Tehran',
      apiBaseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'fresh-token',
      store: store,
      legacyStorage: storage,
      httpClient: client,
    );

    expect(storage.values, isEmpty);
    expect(await runtime.pendingMutationCount(), 1);
    expect(await runtime.pendingAdherenceStates(), <String, String>{
      occurrenceId: 'taken',
    });

    final result = await runtime.flushDetailed();

    expect(result.replayed, 1);
    expect(result.pendingRemaining, 0);
    expect(await runtime.pendingMutationCount(), 0);
    expect(client.requests, hasLength(1));
    expect(
      client.requests.single.headers['authorization'],
      'Bearer fresh-token',
    );
    expect(client.requests.single.headers['idempotency-key'], requestId);
    runtime.close();
    store.close();
  });

  test('explicit Person namespace prevents cross-person replay', () async {
    final database = sqlite3.openInMemory();
    final store = LifeMateLocalHealthStore.forTesting(
      database: database,
      keyBytes: key,
    );
    final otherNamespace = LifeMateLocalNamespace(
      environmentId: 'production',
      accountId: 'account-a',
      personId: 'person-b',
    );
    final outbox = LifeMateLocalMutationOutbox(store: store);
    await outbox.enqueue(
      namespace: otherNamespace,
      mutation: _mutation(
        id: '123e4567-e89b-42d3-a456-426614174952',
        sourceKey: '123e4567-e89b-42d3-a456-426614174052',
      ),
    );
    final client = _RecordingClient(statusCodes: <int>[200]);
    final runtime = await LifeMateSharedOfflineRuntime.open(
      namespace: namespace,
      timeZone: 'UTC',
      apiBaseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'token',
      store: store,
      legacyStorage: _MemoryStorage(),
      httpClient: client,
    );

    final result = await runtime.flushDetailed();

    expect(result.replayed, 0);
    expect(client.requests, isEmpty);
    expect(await outbox.list(namespace: otherNamespace), hasLength(1));
    runtime.close();
    store.close();
  });

  test(
    'missing auth retains shared action for retry without network',
    () async {
      final database = sqlite3.openInMemory();
      final now = DateTime.utc(2026, 9, 5, 3);
      final store = LifeMateLocalHealthStore.forTesting(
        database: database,
        keyBytes: key,
        now: () => now,
      );
      final outbox = LifeMateLocalMutationOutbox(store: store, now: () => now);
      await outbox.enqueue(
        namespace: namespace,
        mutation: _mutation(
          id: '123e4567-e89b-42d3-a456-426614174953',
          sourceKey: '123e4567-e89b-42d3-a456-426614174053',
        ),
      );
      final client = _RecordingClient(statusCodes: <int>[200]);
      final runtime = await LifeMateSharedOfflineRuntime.open(
        namespace: namespace,
        timeZone: 'UTC',
        apiBaseUri: Uri.parse('https://api.example.test'),
        accessToken: () => null,
        store: store,
        legacyStorage: _MemoryStorage(),
        httpClient: client,
        now: () => now,
      );

      final result = await runtime.flushDetailed();

      expect(result.retainedForRetry, 1);
      expect(result.pendingRemaining, 1);
      expect(client.requests, isEmpty);
      expect(await runtime.pendingMutationCount(), 1);
      runtime.close();
      store.close();
    },
  );

  test('terminal conflict is not presented as pending adherence', () async {
    final database = sqlite3.openInMemory();
    final store = LifeMateLocalHealthStore.forTesting(
      database: database,
      keyBytes: key,
    );
    final outbox = LifeMateLocalMutationOutbox(store: store);
    const requestId = '123e4567-e89b-42d3-a456-426614174954';
    const occurrenceId = '123e4567-e89b-42d3-a456-426614174054';
    await outbox.enqueue(
      namespace: namespace,
      mutation: _mutation(id: requestId, sourceKey: occurrenceId),
    );
    final runtime = await LifeMateSharedOfflineRuntime.open(
      namespace: namespace,
      timeZone: 'UTC',
      apiBaseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'token',
      store: store,
      legacyStorage: _MemoryStorage(),
      httpClient: _RecordingClient(statusCodes: <int>[409]),
    );

    final result = await runtime.flushDetailed();

    expect(result.conflicts, 1);
    expect(result.pendingRemaining, 0);
    expect(await runtime.pendingAdherenceStates(), isEmpty);
    final retained = await outbox.get(
      namespace: namespace,
      mutationId: requestId,
    );
    expect(retained?.state, LifeMateMutationSyncState.conflict);
    runtime.close();
    store.close();
  });

  test(
    'account purge requires explicit discard and covers every Person namespace',
    () async {
      final database = sqlite3.openInMemory();
      final store = LifeMateLocalHealthStore.forTesting(
        database: database,
        keyBytes: key,
      );
      final personB = LifeMateLocalNamespace(
        environmentId: 'production',
        accountId: 'account-a',
        personId: 'person-b',
      );
      final accountB = LifeMateLocalNamespace(
        environmentId: 'production',
        accountId: 'account-b',
        personId: 'person-a',
      );
      await LifeMateLocalMutationOutbox(store: store).enqueue(
        namespace: personB,
        mutation: _mutation(
          id: '123e4567-e89b-42d3-a456-426614174956',
          sourceKey: '123e4567-e89b-42d3-a456-426614174056',
        ),
      );
      await store.putProjection(
        namespace: namespace,
        domain: LifeMateLocalProjectionDomain.careEvent,
        recordKey: 'event-a',
        payload: const <String, dynamic>{'kind': 'appointment'},
      );
      await store.putProjection(
        namespace: accountB,
        domain: LifeMateLocalProjectionDomain.careEvent,
        recordKey: 'event-b',
        payload: const <String, dynamic>{'kind': 'appointment'},
      );
      final runtime = await LifeMateSharedOfflineRuntime.open(
        namespace: namespace,
        timeZone: 'UTC',
        apiBaseUri: Uri.parse('https://api.example.test'),
        accessToken: () => 'token',
        store: store,
        legacyStorage: _MemoryStorage(),
        httpClient: _RecordingClient(statusCodes: <int>[]),
      );

      await expectLater(
        runtime.purgeCurrentAccount(discardPendingAndCachedData: false),
        throwsA(isA<LifeMateLocalDataPurgeConfirmationRequiredException>()),
      );
      expect(await store.countNamespace(namespace), 1);
      expect(await store.countNamespace(personB), 1);
      expect(await store.countNamespace(accountB), 1);

      await runtime.purgeCurrentAccount(discardPendingAndCachedData: true);

      expect(await store.countNamespace(namespace), 0);
      expect(await store.countNamespace(personB), 0);
      expect(await store.countNamespace(accountB), 1);
      await expectLater(runtime.pendingMutationCount(), throwsStateError);
      runtime.close();
      store.close();
    },
  );

  test(
    'closed runtime fails visibly without touching external store',
    () async {
      final database = sqlite3.openInMemory();
      final store = LifeMateLocalHealthStore.forTesting(
        database: database,
        keyBytes: key,
      );
      final runtime = await LifeMateSharedOfflineRuntime.open(
        namespace: namespace,
        timeZone: 'UTC',
        apiBaseUri: Uri.parse('https://api.example.test'),
        accessToken: () => 'token',
        store: store,
        legacyStorage: _MemoryStorage(),
        httpClient: _RecordingClient(statusCodes: <int>[200]),
      );

      runtime.close();

      await expectLater(runtime.flushDetailed(), throwsStateError);
      await LifeMateLocalMutationOutbox(store: store).enqueue(
        namespace: namespace,
        mutation: _mutation(
          id: '123e4567-e89b-42d3-a456-426614174955',
          sourceKey: '123e4567-e89b-42d3-a456-426614174055',
        ),
      );
      expect(
        await LifeMateLocalMutationOutbox(
          store: store,
        ).list(namespace: namespace),
        hasLength(1),
      );
      store.close();
    },
  );
}

LifeMateDurableMutation _mutation({
  required String id,
  required String sourceKey,
}) => LifeMateDurableMutation(
  mutationId: id,
  domain: LifeMateMutationDomain.adherence,
  sourceKey: sourceKey,
  method: 'POST',
  endpointPath: '/api/v1/dose-occurrences/$sourceKey/report',
  payload: <String, dynamic>{
    'clientRequestId': id,
    'status': 'taken',
    'expectedVersion': 1,
  },
  createdAtUtc: DateTime.utc(2026, 9, 5, 3),
  timeZone: 'UTC',
);

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

final class _RecordingClient extends http.BaseClient {
  _RecordingClient({required this.statusCodes});

  final List<int> statusCodes;
  final List<http.Request> requests = <http.Request>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is! http.Request) throw StateError('Expected http.Request.');
    requests.add(request);
    final status = statusCodes[requests.length - 1];
    return http.StreamedResponse(
      Stream<List<int>>.value(Uint8List.fromList(utf8.encode('{}'))),
      status,
    );
  }
}
