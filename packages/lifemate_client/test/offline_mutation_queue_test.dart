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
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

void main() {
  test('queue deduplicates the same account + request id mutation', () async {
    final storage = _MemoryStorage();
    final queue = LifeMateOfflineMutationQueue(storage: storage);
    final uri = Uri.parse(
      'https://api.example.test/api/v1/dose-occurrences/'
      '123e4567-e89b-42d3-a456-426614174010/report',
    );

    await queue.enqueue(
      accountId: 'account-a',
      method: 'POST',
      uri: uri,
      body: '{"clientRequestId":"request-1"}',
      clientRequestId: 'request-1',
    );
    await queue.enqueue(
      accountId: 'account-a',
      method: 'POST',
      uri: uri,
      body: '{"clientRequestId":"request-1"}',
      clientRequestId: 'request-1',
    );

    expect(await queue.pendingCount('account-a'), 1);
  });

  test('queued actions are isolated by authenticated account', () async {
    final queue = LifeMateOfflineMutationQueue(storage: _MemoryStorage());
    final uri = Uri.parse('https://api.example.test/api/v1/care-events');

    await queue.enqueue(
      accountId: 'account-a',
      method: 'POST',
      uri: uri,
      body: '{"clientRequestId":"request-a"}',
      clientRequestId: 'request-a',
    );
    await queue.enqueue(
      accountId: 'account-b',
      method: 'POST',
      uri: uri,
      body: '{"clientRequestId":"request-b"}',
      clientRequestId: 'request-b',
    );

    expect(await queue.pendingCount('account-a'), 1);
    expect(await queue.pendingCount('account-b'), 1);
  });

  test('transport journals an idempotent dose action then replays it', () async {
    final storage = _MemoryStorage();
    final queue = LifeMateOfflineMutationQueue(storage: storage);
    var online = false;
    final seen = <http.Request>[];
    final inner = MockClient((request) async {
      seen.add(request);
      if (!online) throw http.ClientException('offline', request.url);
      return http.Response('{}', 200);
    });
    final durable = LifeMateDurableHttpClient(
      accessToken: () => 'fresh-access-token',
      accountId: () => 'account-a',
      queue: queue,
      inner: inner,
    );
    final uri = Uri.parse(
      'https://api.example.test/api/v1/dose-occurrences/'
      '123e4567-e89b-42d3-a456-426614174010/report',
    );
    final body = jsonEncode({
      'clientRequestId': '123e4567-e89b-42d3-a456-426614174099',
      'version': 1,
      'status': 'taken',
      'occurredAtUtc': '2026-08-11T18:00:00Z',
    });

    await expectLater(
      durable.post(
        uri,
        headers: {
          'Authorization': 'Bearer old-token',
          'Content-Type': 'application/json',
        },
        body: body,
      ),
      throwsA(isA<LifeMateOfflineQueuedException>()),
    );
    expect(await queue.pendingCount('account-a'), 1);

    online = true;
    expect(await durable.flushPending(), 1);
    expect(await queue.pendingCount('account-a'), 0);
    expect(seen.length, 2);
    expect(seen.last.headers['authorization'], 'Bearer fresh-access-token');
    expect(seen.last.headers['x-lifemate-replay'], '1');
  });

  test('ordinary non-idempotent writes are never queued automatically', () async {
    final queue = LifeMateOfflineMutationQueue(storage: _MemoryStorage());
    final durable = LifeMateDurableHttpClient(
      accessToken: () => 'token',
      accountId: () => 'account-a',
      queue: queue,
      inner: MockClient((request) async {
        throw http.ClientException('offline', request.url);
      }),
    );

    await expectLater(
      durable.post(
        Uri.parse('https://api.example.test/api/v1/care/invitations'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'clientRequestId': 'not-allowlisted'}),
      ),
      throwsA(isA<http.ClientException>()),
    );
    expect(await queue.pendingCount('account-a'), 0);
  });

  test('expired mutations are pruned instead of replayed forever', () async {
    final storage = _MemoryStorage();
    var now = DateTime.utc(2026, 8, 1);
    final queue = LifeMateOfflineMutationQueue(
      storage: storage,
      now: () => now,
      timeToLive: const Duration(days: 7),
    );
    await queue.enqueue(
      accountId: 'account-a',
      method: 'POST',
      uri: Uri.parse('https://api.example.test/api/v1/care-events'),
      body: '{"clientRequestId":"request-a"}',
      clientRequestId: 'request-a',
    );

    now = DateTime.utc(2026, 8, 9);
    expect(await queue.pendingCount('account-a'), 0);
  });
}
