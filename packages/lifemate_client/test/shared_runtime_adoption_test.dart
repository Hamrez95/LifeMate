import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lifemate_client/lifemate_client.dart';
import 'package:lifemate_core/lifemate_core.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('shared runtime imports actions accepted after runtime open', () async {
    final storage = _MemoryStorage();
    final queue = LifeMateOfflineMutationQueue(storage: storage);
    final database = sqlite3.openInMemory();
    final store = LifeMateLocalHealthStore.forTesting(
      database: database,
      keyBytes: List<int>.generate(32, (index) => index + 1),
    );
    final namespace = LifeMateLocalNamespace(
      environmentId: 'production',
      accountId: 'account-a',
      personId: 'person-a',
    );
    final runtime = await LifeMateSharedOfflineRuntime.open(
      namespace: namespace,
      timeZone: 'Asia/Tehran',
      apiBaseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'fresh-token',
      store: store,
      legacyStorage: storage,
      httpClient: _StatusClient(200),
    );

    const requestId = '123e4567-e89b-42d3-a456-426614174961';
    const occurrenceId = '123e4567-e89b-42d3-a456-426614174061';
    await queue.enqueue(
      accountId: 'account-a',
      method: 'POST',
      uri: Uri.parse(
        'https://api.example.test/api/v1/dose-occurrences/$occurrenceId/report',
      ),
      body: jsonEncode(<String, dynamic>{
        'clientRequestId': requestId,
        'status': 'taken',
        'expectedVersion': 4,
      }),
      clientRequestId: requestId,
    );

    expect(await runtime.pendingMutationCount(), 1);
    expect(storage.values, isEmpty);
    expect(await runtime.pendingAdherenceStates(), <String, String>{
      occurrenceId: 'taken',
    });

    final result = await runtime.flushDetailed();
    expect(result.replayed, 1);
    expect(result.pendingRemaining, 0);

    runtime.close();
    store.close();
  });

  test('durable HTTP replay delegates after shared runtime adoption', () async {
    final queue = LifeMateOfflineMutationQueue(storage: _MemoryStorage());
    final client = LifeMateDurableHttpClient(
      apiBaseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'token',
      accountId: () => 'account-a',
      queue: queue,
      inner: _StatusClient(200),
    );
    var calls = 0;
    client.useReplayDelegate(() async {
      calls += 1;
      return const LifeMateOfflineSyncResult(
        replayed: 2,
        pendingRemaining: 1,
      );
    });

    final result = await client.flushPendingDetailed();

    expect(calls, 1);
    expect(result.replayed, 2);
    expect(result.pendingRemaining, 1);
    client.close();
  });
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
  Future<Map<String, String>> readAll() async => Map<String, String>.from(values);

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

final class _StatusClient extends http.BaseClient {
  _StatusClient(this.statusCode);

  final int statusCode;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(const Stream<List<int>>.empty(), statusCode);
}
