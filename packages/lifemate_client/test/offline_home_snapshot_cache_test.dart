import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lifemate_client/lifemate_client.dart';
import 'package:lifemate_core/lifemate_core.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('Home snapshot cache stays Person scoped and replaces stale window keys', () async {
    final database = sqlite3.openInMemory();
    final store = LifeMateLocalHealthStore.forTesting(
      database: database,
      keyBytes: List<int>.generate(32, (index) => index + 1),
    );
    addTearDown(store.close);
    final storage = _MemoryStorage();

    Future<LifeMateSharedOfflineRuntime> openRuntime(String personId) =>
        LifeMateSharedOfflineRuntime.open(
          namespace: LifeMateOfflineNamespace(
            environmentId: 'production',
            accountId: 'account-a',
            personId: personId,
          ),
          timeZone: 'Asia/Tehran',
          apiBaseUri: Uri.parse('https://api.example.test'),
          accessToken: () => 'token',
          store: store,
          legacyStorage: storage,
        );

    final runtime = await openRuntime('person-a');
    addTearDown(runtime.close);
    await runtime.cacheWellMateHomeSnapshot(
      fromDate: DateTime(2026, 9, 5),
      toDate: DateTime(2026, 9, 12),
      treatmentPlans: <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'plan-a',
          'version': 3,
          'updatedAtUtc': '2026-09-05T05:00:00Z',
          'medication': <String, dynamic>{'name': 'Synthetic medicine'},
        },
      ],
      treatmentOccurrences: <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'dose-a',
          'treatmentPlanId': 'plan-a',
          'scheduledLocalDate': '2026-09-05',
          'scheduledLocalTime': '09:00',
          'status': 'scheduled',
          'version': 4,
          'updatedAtUtc': '2026-09-05T05:01:00Z',
        },
      ],
    );

    final cached = await runtime.readWellMateHomeSnapshot(
      fromDate: DateTime(2026, 9, 5),
      toDate: DateTime(2026, 9, 12),
    );
    expect(cached, isNotNull);
    expect(cached!['offlineCached'], isTrue);
    expect((cached['treatmentPlans'] as List).single['id'], 'plan-a');
    expect((cached['doseOccurrences'] as List).single['id'], 'dose-a');

    final otherPerson = await openRuntime('person-b');
    addTearDown(otherPerson.close);
    expect(
      await otherPerson.readWellMateHomeSnapshot(
        fromDate: DateTime(2026, 9, 5),
        toDate: DateTime(2026, 9, 12),
      ),
      isNull,
    );

    await runtime.cacheWellMateHomeSnapshot(
      fromDate: DateTime(2026, 9, 6),
      toDate: DateTime(2026, 9, 13),
      treatmentPlans: const <Map<String, dynamic>>[],
      treatmentOccurrences: const <Map<String, dynamic>>[],
    );
    expect(await runtime.treatmentPlanProjections(), isEmpty);
    expect(await runtime.treatmentOccurrenceProjections(), isEmpty);
    final knownEmpty = await runtime.readWellMateHomeSnapshot(
      fromDate: DateTime(2026, 9, 6),
      toDate: DateTime(2026, 9, 13),
    );
    expect(knownEmpty, isNotNull);
    expect(knownEmpty!['treatmentPlans'], isEmpty);
    expect(knownEmpty['doseOccurrences'], isEmpty);
  });

  test('Durable client falls back only for transient owner reads', () async {
    final database = sqlite3.openInMemory();
    final store = LifeMateLocalHealthStore.forTesting(
      database: database,
      keyBytes: List<int>.generate(32, (index) => 31 - index),
    );
    addTearDown(store.close);
    final storage = _MemoryStorage();
    final transport = _HomeClient();
    final queue = LifeMateOfflineMutationQueue(storage: storage);
    final client = DurableLifeMateApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'token',
      accountId: () => 'legacy-account-a',
      queue: queue,
      innerHttpClient: transport,
    );
    addTearDown(client.close);

    await client.adoptSharedOfflineRuntime(
      environmentId: 'production',
      accountId: 'canonical-account-a',
      personId: 'person-a',
      legacyAuthenticatedAccountId: 'legacy-account-a',
      timeZone: 'Asia/Tehran',
      localStore: store,
      legacyStorage: storage,
    );

    final online = await client.getHomeSnapshot(
      fromDate: DateTime(2026, 9, 5),
      toDate: DateTime(2026, 9, 12),
    );
    expect(online['offlineCached'], isNull);
    expect((online['doseOccurrences'] as List).single['id'], 'dose-a');

    transport.statusCode = 500;
    final offline = await client.getHomeSnapshot(
      fromDate: DateTime(2026, 9, 5),
      toDate: DateTime(2026, 9, 12),
    );
    expect(offline['offlineCached'], isTrue);
    expect((offline['treatmentPlans'] as List).single['id'], 'plan-a');
    expect((offline['doseOccurrences'] as List).single['id'], 'dose-a');

    transport.statusCode = 401;
    await expectLater(
      client.getHomeSnapshot(
        fromDate: DateTime(2026, 9, 5),
        toDate: DateTime(2026, 9, 12),
      ),
      throwsA(
        isA<LifeMateApiException>().having(
          (error) => error.statusCode,
          'statusCode',
          401,
        ),
      ),
    );
  });
}

final class _MemoryStorage implements LifeMateMutationStorage {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<void> delete(String key) async => _values.remove(key);

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

final class _HomeClient extends http.BaseClient {
  int statusCode = 200;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.path != '/api/v1/home-snapshot') {
      return _json(<String, dynamic>{}, 404);
    }
    if (statusCode != 200) {
      return _json(
        <String, dynamic>{
          'code': statusCode == 401 ? 'authorization_required' : 'unavailable',
          'detail': 'Synthetic failure.',
        },
        statusCode,
      );
    }
    return _json(<String, dynamic>{
      'currentUser': <String, dynamic>{
        'profile': <String, dynamic>{
          'displayName': 'Synthetic owner',
          'timeZone': 'Asia/Tehran',
        },
      },
      'treatmentPlans': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'plan-a',
          'doseText': '1 tablet',
          'version': 3,
          'updatedAtUtc': '2026-09-05T05:00:00Z',
          'medication': <String, dynamic>{'name': 'Synthetic medicine'},
        },
      ],
      'doseOccurrences': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'dose-a',
          'treatmentPlanId': 'plan-a',
          'scheduledLocalDate': '2026-09-05',
          'scheduledLocalTime': '09:00',
          'scheduledAtUtc': '2026-09-05T05:30:00Z',
          'status': 'scheduled',
          'version': 4,
          'updatedAtUtc': '2026-09-05T05:01:00Z',
        },
      ],
      'careEvents': const <Map<String, dynamic>>[],
    }, 200);
  }

  http.StreamedResponse _json(Map<String, dynamic> value, int status) {
    final bytes = utf8.encode(jsonEncode(value));
    return http.StreamedResponse(
      Stream<List<int>>.value(bytes),
      status,
      headers: const <String, String>{'content-type': 'application/json'},
    );
  }
}
