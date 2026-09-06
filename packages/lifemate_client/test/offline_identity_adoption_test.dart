import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test('adopted Account + Person survives store recreation and stays scoped', () async {
    final storage = _MemoryIdentityStorage();
    final first = LifeMateOfflineIdentityAdoptionStore.forTesting(storage);
    await first.remember(
      environmentId: 'https://prod.example.test',
      legacyAccountId: 'legacy-a',
      accountId: 'account-a',
      personId: 'person-a',
      adoptedAtUtc: DateTime.utc(2026, 9, 7),
    );

    final reopened = LifeMateOfflineIdentityAdoptionStore.forTesting(storage);
    final adoption = await reopened.lookup(
      environmentId: 'https://prod.example.test',
      legacyAccountId: 'legacy-a',
    );
    expect(adoption, isNotNull);
    expect(adoption!.accountId, 'account-a');
    expect(adoption.personId, 'person-a');
    expect(adoption.toLocalNamespace().personId, 'person-a');
    expect(
      await reopened.lookup(
        environmentId: 'https://prod.example.test',
        legacyAccountId: 'legacy-b',
      ),
      isNull,
    );
    expect(
      await reopened.lookup(
        environmentId: 'https://staging.example.test',
        legacyAccountId: 'legacy-a',
      ),
      isNull,
    );
  });

  test('remember replaces only the exact environment + authenticated subject', () async {
    final storage = _MemoryIdentityStorage();
    final store = LifeMateOfflineIdentityAdoptionStore.forTesting(storage);
    await store.remember(
      environmentId: 'production',
      legacyAccountId: 'legacy-a',
      accountId: 'account-a',
      personId: 'person-old',
      adoptedAtUtc: DateTime.utc(2026, 9, 6),
    );
    await store.remember(
      environmentId: 'production',
      legacyAccountId: 'legacy-a',
      accountId: 'account-a',
      personId: 'person-new',
      adoptedAtUtc: DateTime.utc(2026, 9, 7),
    );

    final adoption = await store.lookup(
      environmentId: 'production',
      legacyAccountId: 'legacy-a',
    );
    expect(adoption?.personId, 'person-new');
  });

  test('forget removes one account mapping without clearing another account', () async {
    final storage = _MemoryIdentityStorage();
    final store = LifeMateOfflineIdentityAdoptionStore.forTesting(storage);
    await store.remember(
      environmentId: 'production',
      legacyAccountId: 'legacy-a',
      accountId: 'account-a',
      personId: 'person-a',
    );
    await store.remember(
      environmentId: 'production',
      legacyAccountId: 'legacy-b',
      accountId: 'account-b',
      personId: 'person-b',
    );

    await store.forget(
      environmentId: 'production',
      legacyAccountId: 'legacy-a',
    );
    expect(
      await store.lookup(
        environmentId: 'production',
        legacyAccountId: 'legacy-a',
      ),
      isNull,
    );
    expect(
      (await store.lookup(
        environmentId: 'production',
        legacyAccountId: 'legacy-b',
      ))?.personId,
      'person-b',
    );
  });

  test('malformed secure payload fails closed instead of silently resetting', () async {
    final storage = _MemoryIdentityStorage()
      ..values['lifemate.offline.identity_adoptions.v1'] = '{not-json';
    final store = LifeMateOfflineIdentityAdoptionStore.forTesting(storage);

    expect(
      () => store.lookup(
        environmentId: 'production',
        legacyAccountId: 'legacy-a',
      ),
      throwsA(isA<LifeMateOfflineIdentityAdoptionCorruptionException>()),
    );
  });
}

final class _MemoryIdentityStorage implements LifeMateOfflineIdentityStorage {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}
