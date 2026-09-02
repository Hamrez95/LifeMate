import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Encrypted Supabase session persistence for LifeMate mobile clients.
///
/// Raw passwords are never stored here. Supabase remains the owner of access
/// and refresh token rotation; this adapter only changes the device persistence
/// backend used for Supabase's serialized session.
class LifeMateSecureSessionStorage extends LocalStorage {
  LifeMateSecureSessionStorage({
    required this.persistSessionKey,
    FlutterSecureStorage? secureStorage,
    LocalStorage? legacyStorage,
  }) : _secureStorage = secureStorage ?? _defaultSecureStorage,
       _legacyStorage =
           legacyStorage ??
           SharedPreferencesLocalStorage(
             persistSessionKey: persistSessionKey,
           );

  factory LifeMateSecureSessionStorage.forSupabaseUrl(String supabaseUrl) {
    return LifeMateSecureSessionStorage(
      persistSessionKey: supabasePersistSessionKeyForUrl(supabaseUrl),
    );
  }

  static const FlutterSecureStorage _defaultSecureStorage =
      FlutterSecureStorage(
        aOptions: AndroidOptions(
          storageNamespace: 'lifemate_auth_v1',
          migrateOnAlgorithmChange: true,
          migrateWithBackup: true,
          resetOnError: true,
        ),
        // Sessions are device-bound and become available after the first
        // unlock following a reboot. This preserves background reminder/sync
        // access without making the session migrate to a different iPhone.
        iOptions: IOSOptions(
          accessibility: KeychainAccessibility.first_unlock_this_device,
        ),
      );

  /// Matches the key used by `supabase_flutter`'s default
  /// [SharedPreferencesLocalStorage]. Keeping this derivation exact lets an
  /// existing installation migrate its current session without asking the
  /// user to sign in again.
  static String supabasePersistSessionKeyForUrl(String supabaseUrl) {
    final uri = Uri.tryParse(supabaseUrl);
    if (uri == null || uri.host.isEmpty) {
      throw ArgumentError.value(
        supabaseUrl,
        'supabaseUrl',
        'A Supabase URL with a valid host is required.',
      );
    }
    final projectRef = uri.host.split('.').first;
    if (projectRef.isEmpty) {
      throw ArgumentError.value(
        supabaseUrl,
        'supabaseUrl',
        'The Supabase project reference could not be derived.',
      );
    }
    return 'sb-$projectRef-auth-token';
  }

  final String persistSessionKey;
  final FlutterSecureStorage _secureStorage;
  final LocalStorage _legacyStorage;

  bool _initialized = false;

  String get _secureSessionKey =>
      'lifemate.auth.session.v1.$persistSessionKey';

  @override
  Future<void> initialize() async {
    if (_initialized) return;

    await _legacyStorage.initialize();

    final secureSession = await _secureStorage.read(key: _secureSessionKey);
    if (secureSession != null && secureSession.isNotEmpty) {
      // A verified secure copy wins. Remove any stale plaintext-preference
      // copy left by an older LifeMate build.
      await _legacyStorage.removePersistedSession();
      _initialized = true;
      return;
    }

    final legacyHasSession = await _legacyStorage.hasAccessToken();
    if (!legacyHasSession) {
      _initialized = true;
      return;
    }

    final legacySession = await _legacyStorage.accessToken();
    if (legacySession == null || legacySession.isEmpty) {
      await _legacyStorage.removePersistedSession();
      _initialized = true;
      return;
    }

    // Migration is deliberately write -> read/verify -> delete. If secure
    // storage fails, the exception propagates and the legacy copy is retained;
    // we never silently downgrade future persistence back to SharedPreferences.
    await _secureStorage.write(
      key: _secureSessionKey,
      value: legacySession,
    );
    final migratedSession = await _secureStorage.read(key: _secureSessionKey);
    if (migratedSession != legacySession) {
      throw StateError('LifeMate secure session migration verification failed.');
    }

    await _legacyStorage.removePersistedSession();
    _initialized = true;
  }

  @override
  Future<String?> accessToken() {
    return _secureStorage.read(key: _secureSessionKey);
  }

  @override
  Future<bool> hasAccessToken() async {
    final session = await accessToken();
    return session != null && session.isNotEmpty;
  }

  @override
  Future<void> persistSession(String persistSessionString) async {
    await _secureStorage.write(
      key: _secureSessionKey,
      value: persistSessionString,
    );
    // Defense in depth: remove any legacy copy after every successful secure
    // write, not only during the one-time migration.
    await _legacyStorage.removePersistedSession();
  }

  @override
  Future<void> removePersistedSession() async {
    await _secureStorage.delete(key: _secureSessionKey);
    await _legacyStorage.removePersistedSession();
  }
}
