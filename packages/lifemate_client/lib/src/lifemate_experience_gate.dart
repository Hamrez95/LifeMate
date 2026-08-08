import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config.dart';
import 'feature_flags.dart';
import 'health_facts.dart';
import 'lifemate_api_client.dart';
import 'lifemate_auth.dart';

part 'experience_auth.dart';
part 'experience_phone_auth.dart';
part 'experience_preparation.dart';
part 'experience_recovery.dart';
part 'experience_blocking.dart';
part 'experience_ambient.dart';
part 'experience_brand.dart';

typedef LifeMateExperienceAuthenticatedBuilder =
    Widget Function(BuildContext context, LifeMateApiClient apiClient);

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

class _LifeMateExperienceGateState extends State<LifeMateExperienceGate> {
  static const _requestTimeout = Duration(seconds: 20);

  late final SupabaseClient _supabase;
  late final LifeMateApiClient _api;
  StreamSubscription<AuthState>? _authSubscription;
  Session? _session;
  Future<void>? _bootstrap;
  Object? _authStreamError;
  bool _passwordRecovery = false;

  @override
  void initState() {
    super.initState();
    _supabase = Supabase.instance.client;
    _api = LifeMateApiClient(
      baseUri: widget.config.apiBaseUri,
      accessToken: () => _supabase.auth.currentSession?.accessToken,
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
        setState(() {
          _authStreamError = null;
          _session = session;
          _passwordRecovery =
              state.event == AuthChangeEvent.passwordRecovery &&
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
        title: 'ارتباط امن با حساب قطع شد',
        message: 'اتصال اینترنت را بررسی کنید و دوباره تلاش کنید.',
        primaryLabel: 'تلاش دوباره',
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
          final expired =
              snapshot.error is LifeMateApiException &&
              (snapshot.error! as LifeMateApiException).isUnauthorized;
          return _ExperienceBlockingState(
            appName: widget.appName,
            logoAssetPath: widget.logoAssetPath,
            icon: Icons.sync_problem_rounded,
            title: expired ? 'نشست شما منقضی شده است' : 'همگام‌سازی انجام نشد',
            message: expired
                ? 'برای ادامه دوباره وارد حساب شوید.'
                : 'داده‌ای تغییر نکرده است. اتصال را بررسی و دوباره تلاش کنید.',
            primaryLabel: expired ? 'ورود دوباره' : 'تلاش دوباره',
            onPrimary: expired
                ? () => _supabase.auth.signOut()
                : _retryBootstrap,
            secondaryLabel: expired ? null : 'خروج از حساب',
            onSecondary: expired ? null : () => _supabase.auth.signOut(),
          );
        }
        return widget.authenticatedBuilder(context, _api);
      },
    );
  }
}
