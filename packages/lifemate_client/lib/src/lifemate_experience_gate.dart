import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
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
    lifeMateOfflineSyncResult.addListener(_onOfflineSyncResult);
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
        title: isPersian ? feedback.faTitle : feedback.enTitle,
        message: isPersian ? feedback.faMessage : feedback.enMessage,
        type: type,
      );
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _authStreamError != null &&
        _supabase.auth.currentSession != null) {
      setState(() {
        _authStreamError = null;
        _session = _supabase.auth.currentSession;
        if (_session != null) _bootstrap = _bootstrapUser(_session!);
      });
    }
  }

  void _listenToAuth() {
    _authSubscription = _supabase.auth.onAuthStateChange.listen(
      (event) {
        if (!mounted) return;
        if (event.event == AuthChangeEvent.passwordRecovery) {
          setState(() {
            _passwordRecovery = true;
            _authStreamError = null;
          });
          return;
        }
        final next = event.session;
        if (next?.accessToken == _session?.accessToken &&
            event.event != AuthChangeEvent.signedOut) {
          return;
        }
        setState(() {
          _authStreamError = null;
          _session = next;
          _passwordRecovery = false;
          _bootstrap = next == null ? null : _bootstrapUser(next);
        });
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!mounted) return;
        setState(() => _authStreamError = error);
      },
    );
  }

  Future<void> _bootstrapUser(Session session) async {
    await _api.ensureProfile();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    lifeMateOfflineSyncResult.removeListener(_onOfflineSyncResult);
    _authSubscription?.cancel();
    _api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (_passwordRecovery && session != null) {
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
    if (session == null) {
      return _LifeMateAuthExperience(
        appName: widget.appName,
        logoAssetPath: widget.logoAssetPath,
        supabase: _supabase,
      );
    }
    if (_authStreamError != null) {
      return _BlockingExperience(
        title: LifeMateRuntimeLocale.select(
          fa: 'ارتباط امن حساب نیاز به بررسی دارد',
          en: 'Secure account connection needs attention',
        ),
        message: LifeMateRuntimeLocale.select(
          fa: 'برای جلوگیری از نمایش اطلاعات حساب اشتباه، این نشست تا بازیابی ارتباط قابل استفاده نیست.',
          en: 'To avoid showing data from the wrong account, this session is blocked until the secure auth stream recovers.',
        ),
        actionLabel: LifeMateRuntimeLocale.select(
          fa: 'تلاش دوباره',
          en: 'Try again',
        ),
        onAction: () => setState(() {
          _authStreamError = null;
          _session = _supabase.auth.currentSession;
          if (_session != null) _bootstrap = _bootstrapUser(_session!);
        }),
      );
    }
    return FutureBuilder<void>(
      future: _bootstrap,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _PreparationExperience(
            appName: widget.appName,
            logoAssetPath: widget.logoAssetPath,
          );
        }
        if (snapshot.hasError) {
          return _BlockingExperience(
            title: LifeMateRuntimeLocale.select(
              fa: 'آماده‌سازی حساب کامل نشد',
              en: 'Account preparation was not completed',
            ),
            message: LifeMateRuntimeLocale.select(
              fa: 'تا زمانی که هویت و پروفایل سلامت به‌صورت امن آماده نشوند، داده‌های کاربر نمایش داده نمی‌شوند.',
              en: 'User data remains hidden until identity and health-profile preparation completes safely.',
            ),
            actionLabel: LifeMateRuntimeLocale.select(
              fa: 'تلاش دوباره',
              en: 'Try again',
            ),
            onAction: () {
              final current = _supabase.auth.currentSession;
              if (current == null) {
                setState(() {
                  _session = null;
                  _bootstrap = null;
                });
                return;
              }
              setState(() => _bootstrap = _bootstrapUser(current));
            },
          );
        }
        return widget.authenticatedBuilder(context, _api);
      },
    );
  }
}
