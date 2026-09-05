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

  Future<({LifeMateLocalHealthStore store, LifeMateSharedOfflineRuntime runtime})>
  openRuntime() async {
    final store = LifeMateLocalHealthStore.forTesting(
      database: sqlite3.openInMemory(),
      keyBytes: key,
    );
    final runtime = await LifeMateSharedOfflineRuntime.open(
      namespace: namespace,
      timeZone: 'UTC',
      apiBaseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'token',
      store: store,
      legacyStorage: _MemoryStorage(),
      httpClient: _EmptyClient(),
    );
    return (store: store, runtime: runtime);
  }

  test('pulls bounded pages and persists opaque cursor in shared store', () async {
    final opened = await openRuntime();
    final client = _JsonClient(<Map<String, dynamic>>[
      _page(cursor: 'opaque-1', hasMore: true, id: 'event-a'),
      _page(cursor: 'opaque-2', hasMore: false, id: 'event-b'),
    ]);
    final sync = LifeMateCareEventProjectionSync(
      runtime: opened.runtime,
      api: LifeMateIncrementalProjectionApi(
        baseUri: Uri.parse('https://api.example.test'),
        accessToken: () => 'token',
        httpClient: client,
      ),
    );

    final result = await sync.sync(pageSize: 50, maximumPages: 2);

    expect(result.pages, 2);
    expect(result.applied, 2);
    expect(result.deleted, 0);
    expect(result.hasMore, isFalse);
    expect((await opened.runtime.careEventCheckpoint())?.cursor, 'opaque-2');
    expect(client.requests, hasLength(2));
    expect(client.requests.first.url.queryParameters, <String, String>{
      'limit': '50',
    });
    expect(client.requests.last.url.queryParameters, <String, String>{
      'limit': '50',
      'cursor': 'opaque-1',
    });
    for (final request in client.requests) {
      expect(request.url.queryParameters.containsKey('personId'), isFalse);
      expect(request.url.queryParameters.containsKey('accountId'), isFalse);
      expect(request.headers['authorization'], 'Bearer token');
    }

    opened.runtime.close();
    opened.store.close();
  });

  test('side-effect failure retains old cursor and page replays safely', () async {
    final opened = await openRuntime();
    final client = _JsonClient(<Map<String, dynamic>>[
      _page(cursor: 'opaque-1', hasMore: false, id: 'event-a'),
      _page(cursor: 'opaque-1', hasMore: false, id: 'event-a'),
    ]);
    final sync = LifeMateCareEventProjectionSync(
      runtime: opened.runtime,
      api: LifeMateIncrementalProjectionApi(
        baseUri: Uri.parse('https://api.example.test'),
        accessToken: () => 'token',
        httpClient: client,
      ),
    );
    var attempts = 0;

    await expectLater(
      sync.sync(
        beforeCheckpoint: (_) async {
          attempts += 1;
          throw StateError('durable side effect failed');
        },
      ),
      throwsStateError,
    );
    expect(await opened.runtime.careEventCheckpoint(), isNull);

    final result = await sync.sync(
      beforeCheckpoint: (_) async {
        attempts += 1;
      },
    );

    expect(result.applied, 1);
    expect(attempts, 2);
    expect(client.requests, hasLength(2));
    expect((await opened.runtime.careEventCheckpoint())?.cursor, 'opaque-1');

    opened.runtime.close();
    opened.store.close();
  });

  test('non-advancing paged cursor fails before acknowledgement', () async {
    final opened = await openRuntime();
    await opened.runtime.applyCareEventPage(
      page: LifeMateProjectionPullPage(
        nextCursor: 'same-cursor',
        changes: const <LifeMateServerProjectionChange>[],
      ),
    );
    final client = _JsonClient(<Map<String, dynamic>>[
      _page(cursor: 'same-cursor', hasMore: true, id: 'event-a'),
    ]);
    final sync = LifeMateCareEventProjectionSync(
      runtime: opened.runtime,
      api: LifeMateIncrementalProjectionApi(
        baseUri: Uri.parse('https://api.example.test'),
        accessToken: () => 'token',
        httpClient: client,
      ),
    );

    await expectLater(
      sync.sync(),
      throwsA(
        isA<LifeMateApiException>().having(
          (error) => error.code,
          'code',
          'invalid_api_response',
        ),
      ),
    );
    expect(client.requests, hasLength(1));
    expect((await opened.runtime.careEventCheckpoint())?.cursor, 'same-cursor');

    opened.runtime.close();
    opened.store.close();
  });

  test('closed shared runtime rejects projection sync', () async {
    final opened = await openRuntime();
    opened.runtime.close();
    final sync = LifeMateCareEventProjectionSync(
      runtime: opened.runtime,
      api: LifeMateIncrementalProjectionApi(
        baseUri: Uri.parse('https://api.example.test'),
        accessToken: () => 'token',
        httpClient: _JsonClient(<Map<String, dynamic>>[]),
      ),
    );

    await expectLater(sync.sync(), throwsStateError);
    opened.store.close();
  });
}

Map<String, dynamic> _page({
  required String cursor,
  required bool hasMore,
  required String id,
}) => <String, dynamic>{
  'nextCursor': cursor,
  'hasMore': hasMore,
  'changes': <Map<String, dynamic>>[
    <String, dynamic>{
      'recordKey': id,
      'deleted': false,
      'sourceRevision': '1',
      'sourceUpdatedAtUtc': '2026-09-05T00:00:00Z',
      'payload': <String, dynamic>{'id': id, 'kind': 'appointment'},
    },
  ],
};

final class _MemoryStorage implements LifeMateMutationStorage {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

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

final class _EmptyClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(Stream<List<int>>.empty(), 500);
}

final class _JsonClient extends http.BaseClient {
  _JsonClient(this.responses);

  final List<Map<String, dynamic>> responses;
  final List<http.Request> requests = <http.Request>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is! http.Request) throw StateError('Expected http.Request.');
    requests.add(request);
    if (responses.isEmpty) throw StateError('No fake response remains.');
    final body = jsonEncode(responses.removeAt(0));
    return http.StreamedResponse(
      Stream<List<int>>.value(Uint8List.fromList(utf8.encode(body))),
      200,
      headers: const <String, String>{'content-type': 'application/json'},
    );
  }
}
