import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config.dart';
import 'durable_lifemate_api_client.dart';
import 'feature_flags.dart';
import 'health_facts.dart';
import 'lifemate_api_client.dart';
import 'lifemate_auth.dart';
import 'locale_digit_input_formatter.dart';
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
    BuildContext context, LifeMateApiClient apiClient);

/// The polished authentication and account-bootstrap boundary shared by
/// WellMate and CareMate.
///
/// The UI is rendered with native Flutter widgets rather than screenshot
/// backgrounds, so form semantics, text scaling, RTL, validation and error
/// states remain accessible and testable.
class LifeMateExperienceGate extends StatefulWidget {
  const LifeMateExperienceGate({
    required this.config,
    required this.appName,
    required this.logoAssetPath,
    required this.authenticatedBuilder,
    super.key,
  });

  final AppConfig config;
  final String appName;
  final String logoAssetPath;
  final LifeMateExperienceAuthenticatedBuilder authenticatedBuilder;

  @override
  State<LifeMateExperienceGate> createState() => _LifeMateExperienceGateState();
}

class _LifeMateExperienceGateState extends State<LifeMateExperienceGate>
    with WidgetsBindingObserver {
  static const _requestTimeout = Duration(seconds: 20);

  late final SupabaseClient _supabase;
  late final DurableLifeMateApiClient _api;
  StreamSubscription<AuthState>? _authSubscription;
  Session? _session;
  Future<void>? _bootstrap;
  Object? _authStreamError;
  bool _passwordRecovery = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _supabase = Supabase.instance.client;
    _api = DurableLifeMateApiClient(
      baseUri: widget.config.apiBaseUri,
      accessToken: () => _supabase.auth.currentSession?.accessToken,
      accountId: () => _supabase.auth.currentUser?.id,
    );
    _session = _supabase.auth.currentSession;
    if (_session != null) {
      _bootstrap = _bootstrapUser(_session!);
    }
    _listenToAuth();
  }

  void _listenToAuth() {
    _authSubscription?.cancel();
    _authSubscription = _supabase.auth.onAuthStateChange.listen(
      (state) {
        if (!mounted) return;
        final session = state.session;
        final previousUserId = _session?.user.id;
        final nextUserId = session?.user.id;
        if (previousUserId != nextUserId) {
          // The API client instance lives for the lifetime of the auth gate.
          // Profile-photo cache entries are therefore explicitly scoped to
          // the authenticated user so account B can never inherit account A's
          // signed photo URL or avatar fallback.
          LifeMateProfileRefresh.clearForApiClient(_api);
        }
        setState(() {
          _authStreamError = null;
          _session = session;
          _passwordRecovery = state.event == AuthChangeEvent.passwordRecovery &&
              session != null;
          _bootstrap = session == null ? null : _bootstrapUser(session);
        });
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!mounted) return;
        setState(() => _authStreamError = error);
      },
    );
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
    unawaited(_api.flushPendingMutations());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _session != null) {
      unawaited(_api.flushPendingMutations());
    }
  }

  void _retryBootstrap() {
    final session = _session;
    if (session == null) return;
    setState(() => _bootstrap = _bootstrapUser(session));
  }

  void _retryAuthStream() {
    setState(() => _authStreamError = null);
    _listenToAuth();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription?.cancel();
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
          fa: LifeMateRuntimeLocale.select(
            fa: 'ارتباط امن با حساب قطع شد',
            en: "The secure connection to the account was terminated",
          ),
          en: "The secure connection to the account was terminated",
        ),
        message: LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'اتصال اینترنت را بررسی کنید و دوباره تلاش کنید.',
            en: "Check your internet connection and try again.",
          ),
          en: "Check your internet connection and try again.",
        ),
        primaryLabel: LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(fa: 'تلاش دوباره', en: "Try again"),
          en: "Try again",
        ),
        onPrimary: _retryAuthStream,
      );
    }

    if (_session == null) {
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
          final expired = snapshot.error is LifeMateApiException &&
              (snapshot.error! as LifeMateApiException).isUnauthorized;
          return _ExperienceBlockingState(
            appName: widget.appName,
            logoAssetPath: widget.logoAssetPath,
            icon: Icons.sync_problem_rounded,
            title: expired
                ? LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'نشست شما منقضی شده است',
                      en: "Your session has expired",
                    ),
                    en: "Your session has expired",
                  )
                : LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'همگام‌سازی انجام نشد',
                      en: "Synchronization failed",
                    ),
                    en: "Synchronization failed",
                  ),
            message: expired
                ? LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'برای ادامه دوباره وارد حساب شوید.',
                      en: "Log in again to continue.",
                    ),
                    en: "Log in again to continue.",
                  )
                : LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'داده‌ای تغییر نکرده است. اتصال را بررسی و دوباره تلاش کنید.',
                      en: "No data has changed. Check the connection and try again.",
                    ),
                    en: "No data has changed. Check the connection and try again.",
                  ),
            primaryLabel: expired
                ? LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'ورود دوباره',
                      en: "Login again",
                    ),
                    en: "Login again",
                  )
                : LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'تلاش دوباره',
                      en: "Try again",
                    ),
                    en: "Try again",
                  ),
            onPrimary:
                expired ? () => _supabase.auth.signOut() : _retryBootstrap,
            secondaryLabel: expired
                ? null
                : LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'خروج از حساب',
                      en: "Sign out of the account",
                    ),
                    en: "Sign out of the account",
                  ),
            onSecondary: expired ? null : () => _supabase.auth.signOut(),
          );
        }
        return widget.authenticatedBuilder(context, _api);
      },
    );
  }
}
