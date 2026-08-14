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
  Future<Map<String, String>> readAll() async => Map<String, String>.from(values);

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

Uri _doseUri(String id) => Uri.parse(
  'https://api.example.test/api/v1/dose-occurrences/$id/report',
);

void main() {
  test('queue deduplicates the same account + request id mutation', () async {
    final queue = LifeMateOfflineMutationQueue(storage: _MemoryStorage());
    final uri = _doseUri('123e4567-e89b-42d3-a456-426614174010');

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

  test('concurrent queue writes are serialized without lost mutations', () async {
    final queue = LifeMateOfflineMutationQueue(storage: _MemoryStorage());
    await Future.wait([
      for (var i = 0; i < 12; i++)
        queue.enqueue(
          accountId: 'account-a',
          method: 'POST',
          uri: _doseUri(
            '123e4567-e89b-42d3-a456-${(426614174100 + i).toString()}',
          ),
          body: jsonEncode({'clientRequestId': 'request-$i'}),
          clientRequestId: 'request-$i',
        ),
    ]);
    expect(await queue.pendingCount('account-a'), 12);
  });

  test('separate queue instances cannot overwrite each other', () async {
    final storage = _MemoryStorage();
    final foreground = LifeMateOfflineMutationQueue(storage: storage);
    final widget = LifeMateOfflineMutationQueue(storage: storage);

    await Future.wait([
      foreground.enqueue(
        accountId: 'account-a',
        method: 'POST',
        uri: _doseUri('123e4567-e89b-42d3-a456-426614174201'),
        body: '{"clientRequestId":"request-foreground"}',
        clientRequestId: 'request-foreground',
      ),
      widget.enqueue(
        accountId: 'account-a',
        method: 'POST',
        uri: _doseUri('123e4567-e89b-42d3-a456-426614174202'),
        body: '{"clientRequestId":"request-widget"}',
        clientRequestId: 'request-widget',
      ),
    ]);

    expect(await foreground.pendingCount('account-a'), 2);
    expect(await widget.pendingCount('account-a'), 2);
  });

  test('queued actions are isolated by authenticated account', () async {
    final queue = LifeMateOfflineMutationQueue(storage: _MemoryStorage());
    final uri = _doseUri('123e4567-e89b-42d3-a456-426614174010');

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
    final queue = LifeMateOfflineMutationQueue(storage: _MemoryStorage());
    var online = false;
    final seen = <http.Request>[];
    final inner = MockClient((request) async {
      seen.add(request);
      if (!online) throw http.ClientException('offline', request.url);
      return http.Response('{}', 200);
    });
    final durable = LifeMateDurableHttpClient(
      apiBaseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'fresh-access-token',
      accountId: () => 'account-a',
      queue: queue,
      inner: inner,
    );
    final uri = _doseUri('123e4567-e89b-42d3-a456-426614174010');
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

  test('expired session keeps the queued action until a fresh token succeeds', () async {
    final queue = LifeMateOfflineMutationQueue(storage: _MemoryStorage());
    await queue.enqueue(
      accountId: 'account-a',
      method: 'POST',
      uri: _doseUri('123e4567-e89b-42d3-a456-426614174011'),
      body: jsonEncode({
        'clientRequestId': '123e4567-e89b-42d3-a456-426614174098',
        'version': 1,
        'status': 'taken',
        'occurredAtUtc': '2026-08-11T18:00:00Z',
      }),
      clientRequestId: '123e4567-e89b-42d3-a456-426614174098',
    );

    var token = 'expired-token';
    final durable = LifeMateDurableHttpClient(
      apiBaseUri: Uri.parse('https://api.example.test'),
      accessToken: () => token,
      accountId: () => 'account-a',
      queue: queue,
      inner: MockClient((request) async {
        if (request.headers['authorization'] == 'Bearer expired-token') {
          return http.Response('{"code":"unauthorized"}', 401);
        }
        return http.Response('{}', 200);
      }),
    );

    expect(await durable.flushPending(), 0);
    expect(await queue.pendingCount('account-a'), 1);

    token = 'fresh-token';
    expect(await durable.flushPending(), 1);
    expect(await queue.pendingCount('account-a'), 0);
  });

  test('replay stops before another item when authenticated account changes', () async {
    final queue = LifeMateOfflineMutationQueue(storage: _MemoryStorage());
    for (var i = 0; i < 2; i++) {
      await queue.enqueue(
        accountId: 'account-a',
        method: 'POST',
        uri: _doseUri(
          '123e4567-e89b-42d3-a456-${(426614174120 + i).toString()}',
        ),
        body: jsonEncode({'clientRequestId': 'request-$i'}),
        clientRequestId: 'request-$i',
      );
    }
    var account = 'account-a';
    var sends = 0;
    final durable = LifeMateDurableHttpClient(
      apiBaseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'token',
      accountId: () => account,
      queue: queue,
      inner: MockClient((request) async {
        sends++;
        account = 'account-b';
        return http.Response('{}', 200);
      }),
    );

    await durable.flushPending();
    expect(sends, 1);
    expect(await queue.pendingCount('account-a'), 2);
  });

  test('replay never sends a token to an old API origin', () async {
    final queue = LifeMateOfflineMutationQueue(storage: _MemoryStorage());
    await queue.enqueue(
      accountId: 'account-a',
      method: 'POST',
      uri: Uri.parse(
        'https://old.example.test/api/v1/dose-occurrences/'
        '123e4567-e89b-42d3-a456-426614174010/report',
      ),
      body: '{"clientRequestId":"request-old"}',
      clientRequestId: 'request-old',
    );
    var sends = 0;
    final durable = LifeMateDurableHttpClient(
      apiBaseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'fresh-token',
      accountId: () => 'account-a',
      queue: queue,
      inner: MockClient((request) async {
        sends++;
        return http.Response('{}', 200);
      }),
    );

    expect(await durable.flushPending(), 0);
    expect(sends, 0);
    expect(await queue.pendingCount('account-a'), 0);
  });

  test('ordinary non-idempotent writes are never queued automatically', () async {
    final queue = LifeMateOfflineMutationQueue(storage: _MemoryStorage());
    final durable = LifeMateDurableHttpClient(
      apiBaseUri: Uri.parse('https://api.example.test'),
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

  test('durable API projects an offline queued dose as pending state', () async {
    final queue = LifeMateOfflineMutationQueue(storage: _MemoryStorage());
    final api = DurableLifeMateApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'token',
      accountId: () => 'account-a',
      queue: queue,
      innerHttpClient: MockClient((request) async {
        throw http.ClientException('offline', request.url);
      }),
    );

    final result = await api.reportDose(
      occurrenceId: '123e4567-e89b-42d3-a456-426614174010',
      clientRequestId: '123e4567-e89b-42d3-a456-426614174099',
      version: 4,
      status: 'taken',
      occurredAtUtc: DateTime.utc(2026, 8, 11, 18),
    );

    expect(result['pendingSync'], true);
    expect(result['status'], 'pending_sync');
    expect(result['pendingStatus'], 'taken');
    expect(result['version'], 4);
    expect(await queue.pendingCount('account-a'), 1);
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
      uri: _doseUri('123e4567-e89b-42d3-a456-426614174010'),
      body: '{"clientRequestId":"request-a"}',
      clientRequestId: 'request-a',
    );

    now = DateTime.utc(2026, 8, 9);
    expect(await queue.pendingCount('account-a'), 0);
  });
}
