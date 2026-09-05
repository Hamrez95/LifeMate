import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lifemate_core/lifemate_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config.dart';
import 'app_notice.dart';
import 'auth_security_policy.dart';
import 'durable_lifemate_api_client.dart';
import 'feature_flags.dart';
import 'health_facts.dart';
import 'lifemate_api_client.dart';
import 'lifemate_auth.dart';
import 'locale_digit_input_formatter.dart';
import 'offline_sync_feedback.dart';
import 'privacy_safe_product_analytics.dart';
import 'profile_avatar.dart';
import 'runtime_locale.dart';

part 'experience_auth.dart';
part 'experience_phone_auth.dart';
part 'experience_preparation.dart';
part 'experience_recovery.dart';
part 'experience_blocking.dart';
part 'experience_ambient.dart';
part 'experience_brand.dart';

typedef LifeMateExperienceAuthenticatedBuilder = Widget Function(
  BuildContext context,
  LifeMateApiClient apiClient,
);

typedef LifeMateExperienceUnauthenticatedBuilder = Widget Function(
  BuildContext context,
  SupabaseClient supabase,
  String appName,
  String logoAssetPath,
);

/// Authentication/session/bootstrap boundary shared by WellMate and CareMate.
///
/// Session/API ownership remains in `lifemate_client`. Presentation can be
/// supplied by the app/UI layer through [unauthenticatedBuilder], avoiding a
/// dependency cycle from the client package back into `lifemate_ui`.
class LifeMateExperienceGate extends StatefulWidget {
  const LifeMateExperienceGate({
    required this.config,
    required this.appName,
    required this.logoAssetPath,
    required this.authenticatedBuilder,
    this.releaseVersion = 'unknown',
    this.unauthenticatedBuilder,
    this.careEventProjectionBeforeCheckpoint,
    super.key,
  });

  final AppConfig config;
  final String appName;
  final String logoAssetPath;
  final String releaseVersion;
  final LifeMateExperienceAuthenticatedBuilder authenticatedBuilder;
  final LifeMateExperienceUnauthenticatedBuilder? unauthenticatedBuilder;

  /// Optional product-owned pre-checkpoint hook for owner care-event projection
  /// changes. When supplied, bootstrap/reconnect pulls run only after canonical
  /// Account + Person adoption, and the server cursor advances only after this
  /// hook succeeds. Products should use the shared #830 reminder reconciler
  /// here rather than creating another scheduler.
  final LifeMateBeforeProjectionCheckpoint? careEventProjectionBeforeCheckpoint;

  @override
  State<LifeMateExperienceGate> createState() => _LifeMateExperienceGateState();
}

class _LifeMateExperienceGateState extends State<LifeMateExperienceGate>
    with WidgetsBindingObserver {
  static const _requestTimeout = Duration(seconds: 20);

  late final SupabaseClient _supabase;
  late final DurableLifeMateApiClient _api;
  late final LifeMateProductAnalytics _productAnalytics;
  StreamSubscription<AuthState>? _authSubscription;
  Session? _session;
  Future<void>? _bootstrap;
  Object? _authStreamError;
  bool _passwordRecovery = false;
  bool _ownerOfflineSyncInFlight = false;
  String? _trackedAppOpenUserId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    lifeMateOfflineSyncResult.addListener(_onOfflineSyncResult);
    _supabase = Supabase.instance.client;
    _api = DurableLifeMateApiClient(
      baseUri: widget.config.apiBaseUri,
      accessToken: () => _supabase.auth.currentSession?.accessToken,
      accountId: () => _supabase.auth.currentUser?.id,
    );
    _productAnalytics = LifeMateProductAnalytics(
      config: widget.config,
      application: widget.appName,
      releaseVersion: widget.releaseVersion,
      accessToken: () async => _supabase.auth.currentSession?.accessToken,
    );
    // Supabase Flutter restores its persisted session before this gate builds.
    // Always consume that restored session first; never send an OTP merely
    // because the app process restarted or resumed.
    _session = _supabase.auth.currentSession;
    if (_session != null) {
      _bootstrap = _bootstrapUserWithRecovery(_session!);
    }
    _listenToAuth();
  }

  void _onOfflineSyncResult() {
    final result = lifeMateOfflineSyncResult.value;
    if (result == null || !mounted) return;
    lifeMateOfflineSyncResult.value = null;
    final feedback = LifeMateOfflineSyncFeedback.fromResult(result);
    if (!feedback.shouldNotify) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final isPersian = Localizations.localeOf(context).languageCode == 'fa';
      final type = switch (feedback.kind) {
        LifeMateOfflineFeedbackKind.replayed => LifeMateNoticeType.success,
        LifeMateOfflineFeedbackKind.refreshRequired => LifeMateNoticeType.warning,
        LifeMateOfflineFeedbackKind.retryPending => LifeMateNoticeType.info,
        LifeMateOfflineFeedbackKind.noChange => LifeMateNoticeType.info,
      };
      LifeMateNotice.show(
        context,
        title: isPersian ? feedback.titleFa : feedback.titleEn,
        message: isPersian ? feedback.messageFa : feedback.messageEn,
        type: type,
      );
    });
  }

  void _listenToAuth() {
    _authSubscription?.cancel();
    _authSubscription = _supabase.auth.onAuthStateChange.listen(
      (state) {
        if (!mounted) return;
        final session = state.session;
        final previousUserId = _session?.user.id;
        final nextUserId = session?.user.id;
        final shouldSaveCredentialAutofill =
            (state.event == AuthChangeEvent.signedIn &&
                previousUserId == null &&
                nextUserId != null) ||
            (state.event == AuthChangeEvent.userUpdated &&
                _passwordRecovery &&
                nextUserId != null);
        if (shouldSaveCredentialAutofill) {
          // Let Google Password Manager / Samsung Pass / iCloud Keychain and
          // other OS providers save/update the credential only after Supabase
          // has confirmed a real authentication or password-recovery update.
          // LifeMate itself never persists the raw password.
          TextInput.finishAutofillContext(shouldSave: true);
        }
        final keepCurrentBootstrap =
            state.event == AuthChangeEvent.tokenRefreshed &&
            previousUserId != null &&
            previousUserId == nextUserId &&
            _bootstrap != null;
        if (previousUserId != nextUserId) {
          LifeMateProfileRefresh.clearForApiClient(_api);
          _trackedAppOpenUserId = null;
        }
        final nextBootstrap = session == null
            ? null
            : keepCurrentBootstrap
                ? _bootstrap
                : _bootstrapUserWithRecovery(session);
        setState(() {
          _authStreamError = null;
          _session = session;
          _passwordRecovery =
              state.event == AuthChangeEvent.passwordRecovery && session != null;
          _bootstrap = nextBootstrap;
        });
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!mounted) return;
        setState(() => _authStreamError = error);
      },
    );
  }

  Future<void> _bootstrapUserWithRecovery(Session session) async {
    try {
      await _bootstrapUser(session);
    } on LifeMateApiException catch (error) {
      if (!error.isUnauthorized) rethrow;

      // A backend 401 can simply mean the access token expired between
      // restore and the first API request. Refresh exactly once and retry the
      // bootstrap. Do not sign out or trigger another OTP for a recoverable
      // token expiry/network race.
      final response = await _supabase.auth
          .refreshSession()
          .timeout(_requestTimeout);
      final refreshedSession =
          response.session ?? _supabase.auth.currentSession;
      if (refreshedSession == null) rethrow;
      await _bootstrapUser(refreshedSession);
    }
  }

  Future<void> _bootstrapUser(Session session) async {
    final user = session.user;
    final metadata = user.userMetadata ?? const <String, dynamic>{};
    String? displayName;
    for (final key in const ['display_name', 'full_name', 'name']) {
      final candidate = metadata[key]?.toString().trim();
      if (candidate != null && candidate.isNotEmpty) {
        displayName = candidate;
        break;
      }
    }
    await _api
        .bootstrapUser(
          displayName: displayName ?? user.email?.split('@').first,
          email: user.email,
        )
        .timeout(_requestTimeout);
    _trackAuthenticatedAppOpen(user.id);
    unawaited(_syncOwnerOfflineState());
  }

  Future<void> _syncOwnerOfflineState() async {
    if (_ownerOfflineSyncInFlight) return;
    _ownerOfflineSyncInFlight = true;
    try {
      await _api.flushPendingMutationsDetailed();
      final beforeCheckpoint = widget.careEventProjectionBeforeCheckpoint;
      if (beforeCheckpoint != null) {
        await _api.syncCareEventProjections(
          beforeCheckpoint: beforeCheckpoint,
        );
      }
    } on LifeMateApiException catch (error) {
      if (kDebugMode) {
        debugPrint('Owner offline reconnect sync deferred: ${error.code}');
      }
    } on StateError {
      if (kDebugMode) {
        debugPrint('Owner offline reconnect sync deferred before adoption.');
      }
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'lifemate_client.owner_reconnect_sync',
          silent: true,
        ),
      );
    } finally {
      _ownerOfflineSyncInFlight = false;
    }
  }

  void _trackAuthenticatedAppOpen(String userId) {
    if (_trackedAppOpenUserId == userId) return;
    _trackedAppOpenUserId = userId;
    unawaited(
      _productAnalytics.track(
        LifeMateProductEvent.appOpen,
        outcome: LifeMateTelemetryOutcome.success,
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _session != null) {
      // Resuming may replay queued app data, but authentication remains owned
      // by Supabase's restored/auto-refreshed session. Never send OTP or clear
      // auth merely because the lifecycle changed. `app_opened` v1 deliberately
      // represents one authenticated app-process entry, not every foreground
      // resume; a future foreground event can use a separate taxonomy name.
      unawaited(_syncOwnerOfflineState());
    }
  }

  void _retryBootstrap() {
    final session = _session ?? _supabase.auth.currentSession;
    if (session == null) return;
    setState(() => _bootstrap = _bootstrapUserWithRecovery(session));
  }

  void _retryAuthStream() {
    setState(() => _authStreamError = null);
    _listenToAuth();
  }

  @override
  void dispose() {
    lifeMateOfflineSyncResult.removeListener(_onOfflineSyncResult);
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription?.cancel();
    _productAnalytics.close();
    _api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_authStreamError != null) {
      return _ExperienceBlockingState(
        appName: widget.appName,
        logoAssetPath: widget.logoAssetPath,
        icon: Icons.cloud_off_rounded,
        title: LifeMateRuntimeLocale.select(
          fa: 'ارتباط امن با حساب قطع شد',
          en: 'The secure connection to the account was interrupted',
        ),
        message: LifeMateRuntimeLocale.select(
          fa: 'اتصال اینترنت را بررسی کنید و دوباره تلاش کنید.',
          en: 'Check your internet connection and try again.',
        ),
        primaryLabel: LifeMateRuntimeLocale.select(
          fa: 'تلاش دوباره',
          en: 'Try again',
        ),
        onPrimary: _retryAuthStream,
      );
    }

    if (_session == null) {
      final customAuth = widget.unauthenticatedBuilder;
      if (customAuth != null) {
        return customAuth(
          context,
          _supabase,
          widget.appName,
          widget.logoAssetPath,
        );
      }
      return _LifeMateAuthExperience(
        appName: widget.appName,
        logoAssetPath: widget.logoAssetPath,
        supabase: _supabase,
      );
    }

    if (_passwordRecovery) {
      return _PasswordRecoveryExperience(
        appName: widget.appName,
        logoAssetPath: widget.logoAssetPath,
        supabase: _supabase,
        onCancelled: () async {
          await _supabase.auth.signOut();
          if (mounted) setState(() => _passwordRecovery = false);
        },
      );
    }

    return FutureBuilder<void>(
      future: _bootstrap,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _AccountPreparationExperience(
            appName: widget.appName,
            logoAssetPath: widget.logoAssetPath,
          );
        }
        if (snapshot.hasError) {
          final apiError = snapshot.error is LifeMateApiException
              ? snapshot.error! as LifeMateApiException
              : null;
          final deletionPending = apiError?.code == 'account_deletion_pending';
          if (deletionPending) {
            return _ExperienceBlockingState(
              appName: widget.appName,
              logoAssetPath: widget.logoAssetPath,
              icon: Icons.delete_sweep_outlined,
              title: LifeMateRuntimeLocale.select(
                fa: 'حذف حساب در حال انجام است',
                en: 'Account deletion is in progress',
              ),
              message: LifeMateRuntimeLocale.select(
                fa: 'درخواست حذف حساب قبلی هنوز در حال پردازش است. بعد از تکمیل می‌توانی دوباره ثبت‌نام کنی و اطلاعات حذف‌شده بازیابی نمی‌شوند.',
                en: 'Your previous account deletion is still being processed. You can register again after it completes, and deleted data will not be restored.',
              ),
              primaryLabel: LifeMateRuntimeLocale.select(
                fa: 'بررسی دوباره',
                en: 'Check again',
              ),
              onPrimary: _retryBootstrap,
              secondaryLabel: LifeMateRuntimeLocale.select(
                fa: 'خروج از حساب',
                en: 'Sign out',
              ),
              onSecondary: () => _supabase.auth.signOut(),
            );
          }

          final unauthorized = apiError?.isUnauthorized ?? false;
          return _ExperienceBlockingState(
            appName: widget.appName,
            logoAssetPath: widget.logoAssetPath,
            icon: Icons.sync_problem_rounded,
            title: unauthorized
                ? LifeMateRuntimeLocale.select(
                    fa: 'بازیابی نشست کامل نشد',
                    en: 'Session recovery was not completed',
                  )
                : LifeMateRuntimeLocale.select(
                    fa: 'همگام‌سازی انجام نشد',
                    en: 'Synchronization failed',
                  ),
            message: unauthorized
                ? LifeMateRuntimeLocale.select(
                    fa: 'اتصال را بررسی کنید و دوباره تلاش کنید. نشست شما خودکار پاک نمی‌شود.',
                    en: 'Check the connection and retry. Your session will not be cleared automatically.',
                  )
                : LifeMateRuntimeLocale.select(
                    fa: 'داده‌ای تغییر نکرده است. اتصال را بررسی و دوباره تلاش کنید.',
                    en: 'No data changed. Check the connection and try again.',
                  ),
            primaryLabel: unauthorized
                ? LifeMateRuntimeLocale.select(
                    fa: 'تلاش برای بازیابی',
                    en: 'Retry recovery',
                  )
                : LifeMateRuntimeLocale.select(
                    fa: 'تلاش دوباره',
                    en: 'Try again',
                  ),
            onPrimary: _retryBootstrap,
            secondaryLabel: LifeMateRuntimeLocale.select(
              fa: 'خروج از حساب',
              en: 'Sign out',
            ),
            // This is the only user-visible escape hatch here. It requires an
            // explicit tap and is never used as generic 401/network recovery.
            onSecondary: () => _supabase.auth.signOut(),
          );
        }
        return widget.authenticatedBuilder(context, _api);
      },
    );
  }
}
