import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source =
      File('lib/src/lifemate_experience_gate.dart').readAsStringSync();

  test('restored Supabase session is consumed before unauthenticated UI', () {
    expect(source, contains('_session = _supabase.auth.currentSession;'));
    expect(
      source,
      contains('_bootstrap = _bootstrapUserWithRecovery(_session!);'),
    );

    final restoreIndex = source.indexOf(
      '_session = _supabase.auth.currentSession;',
    );
    final authUiIndex = source.indexOf('if (_session == null) {');
    expect(restoreIndex, greaterThanOrEqualTo(0));
    expect(authUiIndex, greaterThan(restoreIndex));
  });

  test('bootstrap 401 refreshes once before surfacing recovery UI', () {
    expect(source, contains('Future<void> _bootstrapUserWithRecovery'));
    expect(source, contains('if (!error.isUnauthorized) rethrow;'));
    expect(
      source,
      contains('.refreshSession()\n          .timeout(_requestTimeout);'),
    );
    expect(source, contains('await _bootstrapUser(refreshedSession);'));
    expect(source, contains('onPrimary: _retryBootstrap,'));
  });

  test('generic unauthorized recovery never signs the user out automatically', () {
    expect(
      source,
      isNot(contains('expired ? () => _supabase.auth.signOut()')),
    );
    expect(
      source,
      isNot(contains('unauthorized ? () => _supabase.auth.signOut()')),
    );
    expect(
      source,
      contains('onSecondary: () => _supabase.auth.signOut(),'),
    );
  });

  test('deletion-pending bootstrap has an explicit privacy-safe blocking state', () {
    expect(source, contains("apiError?.code == 'account_deletion_pending'"));
    expect(source, contains('حذف حساب در حال انجام است'));
    expect(source, contains('Account deletion is in progress'));
    expect(source, contains('اطلاعات حذف‌شده بازیابی نمی‌شوند'));
    expect(source, contains('deleted data will not be restored'));
    expect(source, contains("fa: 'بررسی دوباره'"));
    expect(source, contains("en: 'Check again'"));
  });

  test('token refresh and lifecycle resume do not trigger another OTP', () {
    expect(
      source,
      contains('state.event == AuthChangeEvent.tokenRefreshed'),
    );
    expect(source, contains('keepCurrentBootstrap'));

    final lifecycleStart = source.indexOf('void didChangeAppLifecycleState');
    final lifecycleEnd = source.indexOf('void _retryBootstrap', lifecycleStart);
    expect(lifecycleStart, greaterThanOrEqualTo(0));
    expect(lifecycleEnd, greaterThan(lifecycleStart));
    final lifecycle = source.substring(lifecycleStart, lifecycleEnd);
    expect(lifecycle, contains('unawaited(_syncOwnerOfflineState());'));
    expect(lifecycle, isNot(contains('sendPhoneOtp')));
    expect(lifecycle, isNot(contains('signOut')));
  });

  test('reconnect projection pull cannot bypass the pre-checkpoint hook', () {
    expect(
      source,
      contains(
        'final LifeMateBeforeProjectionCheckpoint? careEventProjectionBeforeCheckpoint;',
      ),
    );
    expect(source, contains('if (_ownerOfflineSyncInFlight) return;'));
    expect(source, contains('await _api.flushPendingMutationsDetailed();'));
    expect(
      source,
      contains(
        'final beforeCheckpoint = widget.careEventProjectionBeforeCheckpoint;',
      ),
    );
    expect(source, contains('if (beforeCheckpoint != null) {'));
    expect(source, contains('await _api.syncCareEventProjections('));
    expect(source, contains('beforeCheckpoint: beforeCheckpoint,'));
  });
}
