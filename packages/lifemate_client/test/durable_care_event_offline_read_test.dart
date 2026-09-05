import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:lifemate_core/lifemate_core.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  const legacyAccountId = 'legacy-auth-account';
  final key = List<int>.generate(32, (index) => index + 1);
  final namespace = LifeMateLocalNamespace(
    environmentId: 'production',
    accountId: 'canonical-account',
    personId: 'person-a',
  );

  test('care-event list falls back to adopted protected projection offline', () async {
    final store = LifeMateLocalHealthStore.forTesting(
      database: sqlite3.openInMemory(),
      keyBytes: key,
    );
    final api = DurableLifeMateApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'token',
      accountId: () => legacyAccountId,
      innerHttpClient: MockClient(
        (_) async => http.Response(
          '{"code":"network_unavailable","message":"offline"}',
          503,
          headers: const {'content-type': 'application/json'},
        ),
      ),
    );
    await api.adoptSharedOfflineRuntime(
      environmentId: namespace.environmentId,
      accountId: namespace.accountId,
      personId: namespace.personId,
      legacyAuthenticatedAccountId: legacyAccountId,
      timeZone: 'Asia/Tehran',
      localStore: store,
      legacyStorage: _MemoryStorage(),
    );
    await store.putProjection(
      namespace: namespace,
      domain: LifeMateLocalProjectionDomain.careEvent,
      recordKey: 'event-in-range',
      payload: const <String, dynamic>{
        'id': 'event-in-range',
        'eventType': 'appointment',
        'scheduledLocalDate': '2026-09-06',
        'scheduledLocalTime': '09:30',
        'timeZone': 'Asia/Tehran',
        'status': 'scheduled',
        'version': 3,
      },
      sourceRevision: '3',
    );
    await store.putProjection(
      namespace: namespace,
      domain: LifeMateLocalProjectionDomain.careEvent,
      recordKey: 'event-out-of-range',
      payload: const <String, dynamic>{
        'id': 'event-out-of-range',
        'eventType': 'injection',
        'scheduledLocalDate': '2026-09-10',
        'scheduledLocalTime': '14:00',
        'timeZone': 'Asia/Tehran',
        'status': 'scheduled',
        'version': 1,
      },
      sourceRevision: '1',
    );

    final values = await api.getCareEvents(
      fromDate: DateTime(2026, 9, 5),
      toDate: DateTime(2026, 9, 7),
    );

    expect(values, hasLength(1));
    expect(values.single['id'], 'event-in-range');
    expect(values.single['eventType'], 'appointment');
    expect(values.single['version'], 3);

    api.close();
    store.close();
  });

  test('authorization errors never fall back to cached care events', () async {
    final store = LifeMateLocalHealthStore.forTesting(
      database: sqlite3.openInMemory(),
      keyBytes: key,
    );
    final api = DurableLifeMateApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'token',
      accountId: () => legacyAccountId,
      innerHttpClient: MockClient(
        (_) async => http.Response(
          '{"code":"forbidden","message":"forbidden"}',
          403,
          headers: const {'content-type': 'application/json'},
        ),
      ),
    );
    await api.adoptSharedOfflineRuntime(
      environmentId: namespace.environmentId,
      accountId: namespace.accountId,
      personId: namespace.personId,
      legacyAuthenticatedAccountId: legacyAccountId,
      timeZone: 'Asia/Tehran',
      localStore: store,
      legacyStorage: _MemoryStorage(),
    );
    await store.putProjection(
      namespace: namespace,
      domain: LifeMateLocalProjectionDomain.careEvent,
      recordKey: 'event-private',
      payload: const <String, dynamic>{
        'id': 'event-private',
        'scheduledLocalDate': '2026-09-06',
      },
    );

    await expectLater(
      api.getCareEvents(
        fromDate: DateTime(2026, 9, 5),
        toDate: DateTime(2026, 9, 7),
      ),
      throwsA(
        isA<LifeMateApiException>().having(
          (error) => error.statusCode,
          'statusCode',
          403,
        ),
      ),
    );

    api.close();
    store.close();
  });
}

final class _MemoryStorage implements LifeMateMutationStorage {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<Map<String, String>> readAll() async =>
      Map<String, String>.from(_values);

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }
}
