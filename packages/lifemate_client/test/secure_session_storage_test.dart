import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  test('derives the exact legacy Supabase persistence key', () {
    expect(
      LifeMateSecureSessionStorage.supabasePersistSessionKeyForUrl(
        'https://bwdvmniywyyijjauipnh.supabase.co',
      ),
      'sb-bwdvmniywyyijjauipnh-auth-token',
    );
  });

  test('migrates an existing SharedPreferences session without logout', () async {
    final legacy = _MemoryLocalStorage('serialized-session-v1');
    final storage = LifeMateSecureSessionStorage(
      persistSessionKey: 'sb-test-auth-token',
      secureStorage: const FlutterSecureStorage(),
      legacyStorage: legacy,
    );

    await storage.initialize();

    expect(await storage.hasAccessToken(), isTrue);
    expect(await storage.accessToken(), 'serialized-session-v1');
    expect(legacy.value, isNull);
    expect(legacy.removeCount, 1);
  });

  test('secure session wins and removes a stale legacy copy', () async {
    final firstLegacy = _MemoryLocalStorage(null);
    final first = LifeMateSecureSessionStorage(
      persistSessionKey: 'sb-test-auth-token',
      secureStorage: const FlutterSecureStorage(),
      legacyStorage: firstLegacy,
    );
    await first.initialize();
    await first.persistSession('secure-session');

    final staleLegacy = _MemoryLocalStorage('stale-session');
    final second = LifeMateSecureSessionStorage(
      persistSessionKey: 'sb-test-auth-token',
      secureStorage: const FlutterSecureStorage(),
      legacyStorage: staleLegacy,
    );
    await second.initialize();

    expect(await second.accessToken(), 'secure-session');
    expect(staleLegacy.value, isNull);
    expect(staleLegacy.removeCount, 1);
  });

  test('new sessions are persisted securely and scrub legacy storage', () async {
    final legacy = _MemoryLocalStorage('old-session');
    final storage = LifeMateSecureSessionStorage(
      persistSessionKey: 'sb-test-auth-token',
      secureStorage: const FlutterSecureStorage(),
      legacyStorage: legacy,
    );
    await storage.initialize();

    legacy.value = 'unexpected-legacy-copy';
    await storage.persistSession('new-secure-session');

    expect(await storage.accessToken(), 'new-secure-session');
    expect(legacy.value, isNull);
  });

  test('sign-out removal clears both secure and legacy persistence', () async {
    final legacy = _MemoryLocalStorage('old-session');
    final storage = LifeMateSecureSessionStorage(
      persistSessionKey: 'sb-test-auth-token',
      secureStorage: const FlutterSecureStorage(),
      legacyStorage: legacy,
    );
    await storage.initialize();
    await storage.persistSession('active-session');

    legacy.value = 'stale-session';
    await storage.removePersistedSession();

    expect(await storage.hasAccessToken(), isFalse);
    expect(await storage.accessToken(), isNull);
    expect(legacy.value, isNull);
  });
}

class _MemoryLocalStorage extends LocalStorage {
  _MemoryLocalStorage(this.value);

  String? value;
  int removeCount = 0;

  @override
  Future<void> initialize() async {}

  @override
  Future<String?> accessToken() async => value;

  @override
  Future<bool> hasAccessToken() async => value != null && value!.isNotEmpty;

  @override
  Future<void> persistSession(String persistSessionString) async {
    value = persistSessionString;
  }

  @override
  Future<void> removePersistedSession() async {
    removeCount += 1;
    value = null;
  }
}
