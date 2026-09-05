import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lifemate_client/lifemate_client.dart';
import 'package:lifemate_client/src/durable_http_client.dart';
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

  test('authenticated legacy alias migrates without crossing accounts', () async {
    final storage = _MemoryStorage();
    final queue = LifeMateOfflineMutationQueue(storage: storage);
    const allowedLegacyAccount = 'legacy-auth-a';
    const unrelatedAccount = 'legacy-auth-b';
    const allowedRequest = '123e4567-e89b-42d3-a456-426614174962';
    const unrelatedRequest = '123e4567-e89b-42d3-a456-426614174963';
    const occurrenceId = '123e4567-e89b-42d3-a456-426614174062';

    for (final entry in <(String, String)>[
      (allowedLegacyAccount, allowedRequest),
      (unrelatedAccount, unrelatedRequest),
    ]) {
      await queue.enqueue(
        accountId: entry.$1,
        method: 'POST',
        uri: Uri.parse(
          'https://api.example.test/api/v1/dose-occurrences/$occurrenceId/report',
        ),
        body: jsonEncode(<String, dynamic>{
          'clientRequestId': entry.$2,
          'status': 'skipped',
          'expectedVersion': 5,
        }),
        clientRequestId: entry.$2,
      );
    }

    final database = sqlite3.openInMemory();
    final store = LifeMateLocalHealthStore.forTesting(
      database: database,
      keyBytes: List<int>.generate(32, (index) => 31 - index),
    );
    final namespace = LifeMateLocalNamespace(
      environmentId: 'production',
      accountId: 'canonical-account-a',
      personId: 'canonical-person-a',
    );
    final runtime = await LifeMateSharedOfflineRuntime.open(
      namespace: namespace,
      timeZone: 'Asia/Tehran',
      apiBaseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'fresh-token',
      legacyAccountIds: const <String>{allowedLegacyAccount},
      store: store,
      legacyStorage: storage,
      httpClient: _StatusClient(200),
    );

    expect(await runtime.pendingMutationCount(), 1);
    final remaining = await storage.readAll();
    expect(remaining.length, 1);
    expect(remaining.values.single, contains(unrelatedAccount));
    expect(remaining.values.single, contains(unrelatedRequest));

    runtime.close();
    store.close();
  });

  test(
    'deferred durable client keeps legacy actions until delegate exists',
    () async {
      final storage = _MemoryStorage();
      final queue = LifeMateOfflineMutationQueue(storage: storage);
      final transport = _CountingClient(200);
      const requestId = '123e4567-e89b-42d3-a456-426614174964';
      const occurrenceId = '123e4567-e89b-42d3-a456-426614174064';
      await queue.enqueue(
        accountId: 'legacy-auth-a',
        method: 'POST',
        uri: Uri.parse(
          'https://api.example.test/api/v1/dose-occurrences/$occurrenceId/report',
        ),
        body: jsonEncode(<String, dynamic>{
          'clientRequestId': requestId,
          'status': 'taken',
          'expectedVersion': 1,
        }),
        clientRequestId: requestId,
      );
      final client = LifeMateDurableHttpClient(
        apiBaseUri: Uri.parse('https://api.example.test'),
        accessToken: () => 'token',
        accountId: () => 'legacy-auth-a',
        queue: queue,
        inner: transport,
      )..deferReplayUntilDelegate();

      final beforeAdoption = await client.flushPendingDetailed();
      expect(beforeAdoption.replayed, 0);
      expect(beforeAdoption.pendingRemaining, 0);
      expect(await queue.pendingCount('legacy-auth-a'), 1);
      expect(transport.sendCount, 0);

      client.useReplayDelegate(() async {
        return const LifeMateOfflineSyncResult(replayed: 1);
      });
      final afterAdoption = await client.flushPendingDetailed();
      expect(afterAdoption.replayed, 1);
      expect(transport.sendCount, 0);
      client.close();
    },
  );

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
      return const LifeMateOfflineSyncResult(replayed: 2, pendingRemaining: 1);
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
  Future<Map<String, String>> readAll() async =>
      Map<String, String>.from(values);

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

final class _CountingClient extends http.BaseClient {
  _CountingClient(this.statusCode);

  final int statusCode;
  int sendCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sendCount += 1;
    return http.StreamedResponse(const Stream<List<int>>.empty(), statusCode);
  }
}
