import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_core/lifemate_core.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  final key = List<int>.generate(32, (index) => index + 1);
  final namespace = LifeMateLocalNamespace(
    environmentId: 'test-environment',
    accountId: 'account-a',
    personId: 'person-a',
  );

  test(
    'stores encrypted person-scoped projection without plaintext selectors',
    () async {
      final database = sqlite3.openInMemory();
      final store = LifeMateLocalHealthStore.forTesting(
        database: database,
        keyBytes: key,
        now: () => DateTime.utc(2026, 9, 4, 12),
      );

      await store.putProjection(
        namespace: namespace,
        domain: LifeMateLocalProjectionDomain.pregnancySnapshot,
        recordKey: 'active-episode',
        payload: const <String, dynamic>{
          'sensitiveDatingValue': '2026-08-01',
          'status': 'active',
        },
        sourceRevision: 'rev-7',
        syncCursor: 'cursor-private-1',
        contentVersion: 'pregnancy-content-v3',
      );

      final raw = database
          .select('SELECT * FROM lifemate_local_projection_records')
          .single;
      final rawText = raw.values
          .map((value) {
            if (value is Uint8List) return base64Encode(value);
            return value.toString();
          })
          .join('|');
      expect(rawText, isNot(contains('account-a')));
      expect(rawText, isNot(contains('person-a')));
      expect(rawText, isNot(contains('pregnancy_snapshot')));
      expect(rawText, isNot(contains('2026-08-01')));
      expect(rawText, isNot(contains('cursor-private-1')));

      final restored = await store.readProjection(
        namespace: namespace,
        domain: LifeMateLocalProjectionDomain.pregnancySnapshot,
        recordKey: 'active-episode',
      );
      expect(restored, isNotNull);
      expect(restored!.payload['sensitiveDatingValue'], '2026-08-01');
      expect(restored.sourceRevision, 'rev-7');
      expect(restored.syncCursor, 'cursor-private-1');
      expect(restored.storedAtUtc, DateTime.utc(2026, 9, 4, 12));

      store.close();
    },
  );

  test('isolates environment, account and Person namespaces', () async {
    final database = sqlite3.openInMemory();
    final store = LifeMateLocalHealthStore.forTesting(
      database: database,
      keyBytes: key,
    );
    final personB = LifeMateLocalNamespace(
      environmentId: 'test-environment',
      accountId: 'account-a',
      personId: 'person-b',
    );
    final accountB = LifeMateLocalNamespace(
      environmentId: 'test-environment',
      accountId: 'account-b',
      personId: 'person-a',
    );
    final otherEnvironment = LifeMateLocalNamespace(
      environmentId: 'other-environment',
      accountId: 'account-a',
      personId: 'person-a',
    );

    for (final entry in <(LifeMateLocalNamespace, String)>[
      (namespace, 'owner-a'),
      (personB, 'person-b'),
      (accountB, 'account-b'),
      (otherEnvironment, 'other-environment'),
    ]) {
      await store.putProjection(
        namespace: entry.$1,
        domain: LifeMateLocalProjectionDomain.treatmentPlan,
        recordKey: 'same-record-key',
        payload: <String, dynamic>{'value': entry.$2},
      );
    }

    expect(
      (await store.readProjection(
        namespace: namespace,
        domain: LifeMateLocalProjectionDomain.treatmentPlan,
        recordKey: 'same-record-key',
      ))!.payload['value'],
      'owner-a',
    );
    expect(await store.countNamespace(namespace), 1);
    expect(await store.countNamespace(personB), 1);
    expect(await store.countNamespace(accountB), 1);
    expect(await store.countNamespace(otherEnvironment), 1);

    await store.purgeAccount(
      environmentId: 'test-environment',
      accountId: 'account-a',
    );
    expect(await store.countNamespace(namespace), 0);
    expect(await store.countNamespace(personB), 0);
    expect(await store.countNamespace(accountB), 1);
    expect(await store.countNamespace(otherEnvironment), 1);

    await store.purgeEnvironment('other-environment');
    expect(await store.countNamespace(otherEnvironment), 0);
    store.close();
  });

  test('tampered encrypted payload fails closed', () async {
    final database = sqlite3.openInMemory();
    final store = LifeMateLocalHealthStore.forTesting(
      database: database,
      keyBytes: key,
    );
    await store.putProjection(
      namespace: namespace,
      domain: LifeMateLocalProjectionDomain.healthObservation,
      recordKey: 'observation-1',
      payload: const <String, dynamic>{'value': 120},
    );

    database.execute(
      'UPDATE lifemate_local_projection_records SET ciphertext = ?',
      <Object?>[
        Uint8List.fromList(<int>[1, 2, 3, 4]),
      ],
    );

    await expectLater(
      store.readProjection(
        namespace: namespace,
        domain: LifeMateLocalProjectionDomain.healthObservation,
        recordKey: 'observation-1',
      ),
      throwsA(isA<LifeMateLocalStoreCorruptionException>()),
    );
    store.close();
  });

  test('rejects future schema instead of opening with unknown semantics', () {
    final database = sqlite3.openInMemory();
    database.execute('PRAGMA user_version = 99');
    expect(
      () => LifeMateLocalHealthStore.forTesting(
        database: database,
        keyBytes: key,
      ),
      throwsA(isA<LifeMateLocalStoreSchemaException>()),
    );
    database.close();
  });

  test('failed schema migration leaves user_version unchanged', () {
    final database = sqlite3.openInMemory();
    database.execute(
      'CREATE TABLE lifemate_local_projection_records (unexpected TEXT)',
    );

    expect(
      () => LifeMateLocalHealthStore.forTesting(
        database: database,
        keyBytes: key,
      ),
      throwsA(anything),
    );
    expect(database.select('PRAGMA user_version').first['user_version'], 0);
    database.close();
  });

  test(
    'pending mutation projection survives close/reopen and missing key fails',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'lifemate-core-test-',
      );
      final path =
          '${directory.path}${Platform.pathSeparator}lifemate-local.sqlite3';
      final keyStore = _MemoryKeyStore(seed: key);

      final first = await LifeMateLocalHealthStore.openAtPath(
        path,
        keyStore: keyStore,
        now: () => DateTime.utc(2026, 9, 4, 13),
      );
      await first.putProjection(
        namespace: namespace,
        domain: LifeMateLocalProjectionDomain.pendingMutation,
        recordKey: 'client-mutation-1',
        payload: const <String, dynamic>{
          'operation': 'check_in',
          'state': 'pending',
        },
      );
      first.close();

      final fileText = latin1.decode(File(path).readAsBytesSync());
      expect(fileText, isNot(contains('account-a')));
      expect(fileText, isNot(contains('person-a')));
      expect(fileText, isNot(contains('pending_mutation')));
      expect(fileText, isNot(contains('check_in')));

      final reopened = await LifeMateLocalHealthStore.openAtPath(
        path,
        keyStore: keyStore,
      );
      final mutation = await reopened.readProjection(
        namespace: namespace,
        domain: LifeMateLocalProjectionDomain.pendingMutation,
        recordKey: 'client-mutation-1',
      );
      expect(mutation, isNotNull);
      expect(mutation!.payload['state'], 'pending');
      reopened.close();

      await expectLater(
        LifeMateLocalHealthStore.openAtPath(
          path,
          keyStore: _MemoryKeyStore(seed: key),
        ),
        throwsA(isA<LifeMateLocalStoreKeyUnavailableException>()),
      );

      directory.deleteSync(recursive: true);
    },
  );

  test('bounded payload refuses oversized local health records', () async {
    final database = sqlite3.openInMemory();
    final store = LifeMateLocalHealthStore.forTesting(
      database: database,
      keyBytes: key,
    );
    final tooLarge = List<String>.filled(
      LifeMateLocalHealthStore.maximumPlaintextEnvelopeBytes + 1,
      'x',
    ).join();

    await expectLater(
      store.putProjection(
        namespace: namespace,
        domain: LifeMateLocalProjectionDomain.pregnancyContent,
        recordKey: 'oversized',
        payload: <String, dynamic>{'body': tooLarge},
      ),
      throwsA(isA<ArgumentError>()),
    );
    store.close();
  });
}

final class _MemoryKeyStore implements LifeMateLocalKeyStore {
  _MemoryKeyStore({required List<int> seed}) : _seed = List<int>.from(seed);

  final List<int> _seed;
  List<int>? _value;

  @override
  Future<List<int>> createKey() async {
    _value = List<int>.from(_seed);
    return List<int>.from(_value!);
  }

  @override
  Future<void> deleteKey() async {
    _value = null;
  }

  @override
  Future<List<int>?> readKey() async =>
      _value == null ? null : List<int>.from(_value!);
}
