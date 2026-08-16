import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:lifemate_client/src/durable_http_client.dart';

class _MemoryStorage implements LifeMateMutationStorage {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<Map<String, String>> readAll() async =>
      Map<String, String>.from(values);

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

Uri _doseUri(String suffix) => Uri.parse(
      'https://api.example.test/api/v1/dose-occurrences/'
      '123e4567-e89b-42d3-a456-$suffix/report',
    );

Future<LifeMateOfflineMutationQueue> _queueOne({
  String requestId = '123e4567-e89b-42d3-a456-426614174901',
}) async {
  final queue = LifeMateOfflineMutationQueue(storage: _MemoryStorage());
  await queue.enqueue(
    accountId: 'account-a',
    method: 'POST',
    uri: _doseUri('426614174900'),
    body: jsonEncode(<String, Object>{
      'clientRequestId': requestId,
      'version': 1,
      'status': 'taken',
      'occurredAtUtc': '2026-08-16T06:00:00Z',
    }),
    clientRequestId: requestId,
  );
  return queue;
}

void main() {
  test('stale 409 replay becomes refresh-required conflict, not overwrite',
      () async {
    final queue = await _queueOne();
    final durable = LifeMateDurableHttpClient(
      apiBaseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'fresh-token',
      accountId: () => 'account-a',
      queue: queue,
      inner: MockClient(
        (_) async => http.Response('{"code":"version_conflict"}', 409),
      ),
    );

    final result = await durable.flushPendingDetailed();

    expect(result.replayed, 0);
    expect(result.conflicts, 1);
    expect(result.needsRefresh, true);
    expect(result.pendingRemaining, 0);
    expect(await queue.pendingCount('account-a'), 0);
    expect(result.toJson().keys.toSet(), <String>{
      'replayed',
      'conflicts',
      'terminalRejected',
      'retainedForRetry',
      'removedUnsafe',
      'pendingRemaining',
      'needsRefresh',
    });
  });

  test('retryable server failure retains the exact queued mutation', () async {
    final queue = await _queueOne();
    final durable = LifeMateDurableHttpClient(
      apiBaseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'fresh-token',
      accountId: () => 'account-a',
      queue: queue,
      inner: MockClient((_) async => http.Response('', 503)),
    );

    final result = await durable.flushPendingDetailed();

    expect(result.retainedForRetry, 1);
    expect(result.hasPending, true);
    expect(result.pendingRemaining, 1);
    expect(await queue.pendingCount('account-a'), 1);
  });

  test('timeout-after-commit retry keeps one mutation then replays same key',
      () async {
    const requestId = '123e4567-e89b-42d3-a456-426614174902';
    final queue = await _queueOne(requestId: requestId);
    var attempts = 0;
    final seenBodies = <String>[];
    final inner = MockClient((request) async {
      attempts += 1;
      seenBodies.add(request.body);
      if (attempts == 1) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        return http.Response('{}', 200);
      }
      return http.Response('{}', 200);
    });
    final durable = LifeMateDurableHttpClient(
      apiBaseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'fresh-token',
      accountId: () => 'account-a',
      queue: queue,
      inner: inner,
      transportTimeout: const Duration(milliseconds: 10),
    );

    final first = await durable.flushPendingDetailed();
    expect(first.retainedForRetry, 1);
    expect(first.pendingRemaining, 1);

    final second = await durable.flushPendingDetailed();
    expect(second.replayed, 1);
    expect(second.pendingRemaining, 0);
    expect(seenBodies, hasLength(2));
    expect(seenBodies[0], seenBodies[1]);
    expect(seenBodies[1], contains(requestId));
  });

  test('successful reconnect reports replayed without user or health payload',
      () async {
    final queue = await _queueOne();
    final durable = LifeMateDurableHttpClient(
      apiBaseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'fresh-token',
      accountId: () => 'account-a',
      queue: queue,
      inner: MockClient((request) async {
        expect(request.headers['x-lifemate-replay'], '1');
        return http.Response('{}', 200);
      }),
    );

    final result = await durable.flushPendingDetailed();
    final encoded = jsonEncode(result.toJson());

    expect(result.replayed, 1);
    expect(result.needsRefresh, false);
    expect(result.pendingRemaining, 0);
    expect(encoded, isNot(contains('account-a')));
    expect(encoded, isNot(contains('123e4567')));
    expect(encoded, isNot(contains('taken')));
  });

  test('durable API publishes bounded sync feedback for UI refresh notices',
      () async {
    final queue = await _queueOne();
    final api = DurableLifeMateApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'fresh-token',
      accountId: () => 'account-a',
      queue: queue,
      innerHttpClient: MockClient((_) async => http.Response('', 409)),
    );

    lifeMateOfflineSyncResult.value = null;
    final result = await api.flushPendingMutationsDetailed();

    expect(result.conflicts, 1);
    expect(lifeMateOfflineSyncResult.value?.conflicts, 1);
    expect(lifeMateOfflineSyncResult.value?.needsRefresh, true);
  });
}
