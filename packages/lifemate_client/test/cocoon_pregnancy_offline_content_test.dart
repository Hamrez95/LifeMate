import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:lifemate_core/lifemate_core.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  final key = Uint8List.fromList(List<int>.generate(32, (index) => index + 1));
  final owner = LifeMateLocalNamespace(
    environmentId: 'production',
    accountId: 'account-a',
    personId: 'person-a',
  );
  final otherPerson = LifeMateLocalNamespace(
    environmentId: 'production',
    accountId: 'account-a',
    personId: 'person-b',
  );

  test('approved pregnancy content stays Person scoped with version metadata', () async {
    final store = LifeMateLocalHealthStore.forTesting(
      database: sqlite3.openInMemory(),
      keyBytes: key,
    );
    final ownerRuntime = await _openRuntime(store, owner);
    final otherRuntime = await _openRuntime(store, otherPerson);
    final ownerCache = await CocoonPregnancyOfflineContentCache.open(
      runtime: ownerRuntime,
      store: store,
    );
    final otherCache = await CocoonPregnancyOfflineContentCache.open(
      runtime: otherRuntime,
      store: store,
    );
    addTearDown(() {
      ownerCache.close();
      otherCache.close();
      ownerRuntime.close();
      otherRuntime.close();
      store.close();
    });

    await ownerCache.writeApprovedContent(
      recordKey: 'weekly:4:fa',
      contentVersion: 'pregnancy.week.4.summary:v1:fa',
      ruleVersion: 'pregnancy-clinical-v1',
      payload: const <String, dynamic>{
        'gestationalWeek': 4,
        'requestedLocale': 'fa',
        'selectedLocale': 'fa',
        'usedLocaleFallback': false,
        'usedSafetyFallback': false,
        'title': 'approved-copy',
      },
    );

    final cached = await ownerCache.readApprovedContent(recordKey: 'weekly:4:fa');
    expect(cached, isNotNull);
    expect(cached!.contentVersion, 'pregnancy.week.4.summary:v1:fa');
    expect(cached.ruleVersion, 'pregnancy-clinical-v1');
    expect(cached.payload['gestationalWeek'], 4);
    expect(cached.payload['usedLocaleFallback'], isFalse);
    expect(
      await otherCache.readApprovedContent(recordKey: 'weekly:4:fa'),
      isNull,
    );
  });

  test('cache rejects free-form metadata keys instead of persisting PHI-like text', () async {
    final store = LifeMateLocalHealthStore.forTesting(
      database: sqlite3.openInMemory(),
      keyBytes: key,
    );
    final runtime = await _openRuntime(store, owner);
    final cache = await CocoonPregnancyOfflineContentCache.open(
      runtime: runtime,
      store: store,
    );
    addTearDown(() {
      cache.close();
      runtime.close();
      store.close();
    });

    expect(
      () => cache.writeApprovedContent(
        recordKey: 'week 4 private note',
        contentVersion: 'v1',
        payload: const <String, dynamic>{'title': 'copy'},
      ),
      throwsArgumentError,
    );
    expect(
      await cache.readApprovedContent(recordKey: 'weekly:4:fa'),
      isNull,
    );
  });

  test('delete removes only the addressed approved content record', () async {
    final store = LifeMateLocalHealthStore.forTesting(
      database: sqlite3.openInMemory(),
      keyBytes: key,
    );
    final runtime = await _openRuntime(store, owner);
    final cache = await CocoonPregnancyOfflineContentCache.open(
      runtime: runtime,
      store: store,
    );
    addTearDown(() {
      cache.close();
      runtime.close();
      store.close();
    });

    await cache.writeApprovedContent(
      recordKey: 'weekly:4:en',
      contentVersion: 'week4:v1:en',
      payload: const <String, dynamic>{'gestationalWeek': 4},
    );
    await cache.writeApprovedContent(
      recordKey: 'weekly:5:en',
      contentVersion: 'week5:v1:en',
      payload: const <String, dynamic>{'gestationalWeek': 5},
    );

    await cache.deleteApprovedContent(recordKey: 'weekly:4:en');
    expect(await cache.readApprovedContent(recordKey: 'weekly:4:en'), isNull);
    expect(await cache.readApprovedContent(recordKey: 'weekly:5:en'), isNotNull);
  });
}

Future<LifeMateSharedOfflineRuntime> _openRuntime(
  LifeMateLocalHealthStore store,
  LifeMateLocalNamespace namespace,
) => LifeMateSharedOfflineRuntime.open(
  namespace: LifeMateOfflineNamespace(
    environmentId: namespace.environmentId,
    accountId: namespace.accountId,
    personId: namespace.personId,
  ),
  timeZone: 'Asia/Tehran',
  apiBaseUri: Uri.parse('https://api.example.test'),
  accessToken: () => 'token',
  store: store,
  legacyStorage: _MemoryStorage(),
);

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
