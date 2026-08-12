import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config.dart';
import 'feature_flags.dart';
import 'lifemate_api_client.dart';
import 'lifemate_auth.dart';
import 'runtime_locale.dart';

typedef SecureAuthenticatedBuilder =
    Widget Function(BuildContext context, LifeMateApiClient apiClient);

/// Authentication and session boundary shared by WellMate and CareMate.
///
/// Email/password is the default provider. Optional providers are only added to
/// the widget tree when their compile-time feature flag is explicitly enabled.
class LifeMateSessionGate extends StatefulWidget {
  const LifeMateSessionGate({
    required this.config,
    required this.appName,
    required this.logoAssetPath,
    required this.authenticatedBuilder,
    super.key,
  });

  final AppConfig config;
  final String appName;
  final String logoAssetPath;
  final SecureAuthenticatedBuilder authenticatedBuilder;

  @override
  State<LifeMateSessionGate> createState() => _LifeMateSessionGateState();
}

class _LifeMateSessionGateState extends State<LifeMateSessionGate> {
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
      return _BlockingState(
        appName: widget.appName,
        logoAssetPath: widget.logoAssetPath,
        icon: Icons.cloud_off_rounded,
        title: LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'ارتباط امن با حساب کاربری قطع شد',
            en: "The secure connection with the user account was lost",
          ),
          en: "The secure connection with the user account was lost",
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
      return _EmailPasswordAuthScreen(
        appName: widget.appName,
        logoAssetPath: widget.logoAssetPath,
        supabase: _supabase,
      );
    }

    if (_passwordRecovery) {
      return _PasswordRecoveryScreen(
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
          return _BlockingState(
            appName: widget.appName,
            logoAssetPath: widget.logoAssetPath,
            icon: Icons.health_and_safety_rounded,
            title: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'در حال آماده‌سازی حساب',
                en: "Preparing account",
              ),
              en: "Preparing account",
            ),
            message: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'اطلاعات حساب شما به‌صورت امن همگام می‌شود.',
                en: "Your account information is securely synced.",
              ),
              en: "Your account information is securely synced.",
            ),
          );
        }
        if (snapshot.hasError) {
          final expired =
              snapshot.error is LifeMateApiException &&
              (snapshot.error! as LifeMateApiException).isUnauthorized;
          return _BlockingState(
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
            onPrimary: expired
                ? () => _supabase.auth.signOut()
                : _retryBootstrap,
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

enum _AuthMode { signIn, signUp }

class _EmailPasswordAuthScreen extends StatefulWidget {
  const _EmailPasswordAuthScreen({
    required this.appName,
    required this.logoAssetPath,
    required this.supabase,
  });

  final String appName;
  final String logoAssetPath;
  final SupabaseClient supabase;

  @override
  State<_EmailPasswordAuthScreen> createState() =>
      _EmailPasswordAuthScreenState();
}

class _EmailPasswordAuthScreenState extends State<_EmailPasswordAuthScreen> {
  static const _requestTimeout = Duration(seconds: 20);

  final _formKey = GlobalKey<FormState>();
  final _displayName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  _AuthMode _mode = _AuthMode.signIn;
  bool _busy = false;
  bool _obscure = true;
  bool _obscureConfirm = true;
  String? _error;
  String? _success;

  bool get _isCareMate => widget.appName.toLowerCase().contains('care');
  Color get _primary =>
      _isCareMate ? const Color(0xFF4A90E2) : const Color(0xFF10B981);
  Color get _background =>
      _isCareMate ? const Color(0xFFE2EFFF) : const Color(0xFFF1FAF5);

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (_busy || !_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
      _success = null;
    });
    try {
      if (_mode == _AuthMode.signIn) {
        await widget.supabase.auth
            .signInWithPassword(
              email: _email.text.trim(),
              password: _password.text,
            )
            .timeout(_requestTimeout);
      } else {
        final response = await widget.supabase.auth
            .signUp(
              email: _email.text.trim(),
              password: _password.text,
              emailRedirectTo: LifeMateAuth.callbackUrlForApp(widget.appName),
              data: {'display_name': _displayName.text.trim()},
            )
            .timeout(_requestTimeout);
        if (!mounted) return;
        if (response.session == null) {
          setState(() {
            _success = LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'حساب ساخته شد. اکنون می‌توانید وارد شوید.',
                en: "Account created. You can now login.",
              ),
              en: "Account created. You can now login.",
            );
            _mode = _AuthMode.signIn;
            _password.clear();
            _confirmPassword.clear();
          });
        }
      }
    } on TimeoutException {
      if (mounted) {
        setState(
          () => _error = LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'پاسخی دریافت نشد. اتصال را بررسی و دوباره تلاش کنید.',
              en: "No response received. Check the connection and try again.",
            ),
            en: "No response received. Check the connection and try again.",
          ),
        );
      }
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = _friendlyAuthError(error));
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'ارتباط با سرور برقرار نشد. دوباره تلاش کنید.',
              en: "The connection with the server could not be established. Try again.",
            ),
            en: "The connection with the server could not be established. Try again.",
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendPasswordReset() async {
    final email = _email.text.trim();
    if (!_looksLikeEmail(email)) {
      setState(() {
        _error = LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'ابتدا ایمیل معتبر خود را وارد کنید.',
            en: "First enter your valid email.",
          ),
          en: "First enter your valid email.",
        );
        _success = null;
      });
      return;
    }
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _success = null;
    });
    try {
      await widget.supabase.auth
          .resetPasswordForEmail(
            email,
            redirectTo: LifeMateAuth.callbackUrlForApp(widget.appName),
          )
          .timeout(_requestTimeout);
      if (mounted) {
        setState(() {
          _success = LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'اگر حسابی با این ایمیل وجود داشته باشد، لینک بازیابی ارسال می‌شود.',
              en: "If there is an account with this email, a recovery link will be sent.",
            ),
            en: "If there is an account with this email, a recovery link will be sent.",
          );
        });
      }
    } on TimeoutException {
      if (mounted) {
        setState(
          () => _error = LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'پاسخی دریافت نشد. کمی بعد دوباره تلاش کنید.',
              en: "No response received. Try again later.",
            ),
            en: "No response received. Try again later.",
          ),
        );
      }
    } on AuthException catch (error) {
      if (!mounted) return;
      if (error.message.toLowerCase().contains('rate limit')) {
        setState(
          () => _error = LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'تعداد درخواست‌ها زیاد است؛ کمی بعد دوباره تلاش کنید.',
              en: "The number of requests is high; Try again later.",
            ),
            en: "The number of requests is high; Try again later.",
          ),
        );
      } else {
        setState(() {
          _success = LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'اگر حسابی با این ایمیل وجود داشته باشد، لینک بازیابی ارسال می‌شود.',
              en: "If there is an account with this email, a recovery link will be sent.",
            ),
            en: "If there is an account with this email, a recovery link will be sent.",
          );
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'ارسال درخواست بازیابی انجام نشد.',
              en: "Failed to send recovery request.",
            ),
            en: "Failed to send recovery request.",
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    if (_busy || !LifeMateFeatureFlags.googleAuthEnabled) return;
    setState(() {
      _busy = true;
      _error = null;
      _success = null;
    });
    try {
      final launched = await LifeMateAuth.signInWithGoogle(
        appName: widget.appName,
      ).timeout(_requestTimeout);
      if (!launched && mounted) {
        setState(
          () => _error = LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'صفحه ورود گوگل باز نشد. دوباره تلاش کنید.',
              en: "The Google login page did not open. Try again.",
            ),
            en: "The Google login page did not open. Try again.",
          ),
        );
      }
    } on TimeoutException {
      if (mounted)
        setState(
          () => _error = LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'درخواست ورود به پایان زمان مجاز رسید.',
              en: "The login request has timed out.",
            ),
            en: "The login request has timed out.",
          ),
        );
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = _friendlyAuthError(error));
    } catch (_) {
      if (mounted)
        setState(
          () => _error = LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'ورود با گوگل انجام نشد.',
              en: "Login with Google failed.",
            ),
            en: "Login with Google failed.",
          ),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _changeMode(_AuthMode mode) {
    if (_busy || mode == _mode) return;
    setState(() {
      _mode = mode;
      _error = null;
      _success = null;
      _formKey.currentState?.reset();
    });
  }

  @override
  void dispose() {
    _displayName.dispose();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSignUp = _mode == _AuthMode.signUp;
    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(22, 24, 22, 32),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 440),
              child: AutofillGroup(
                child: Column(
                  children: [
                    Image.asset(
                      widget.logoAssetPath,
                      height: 82,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Icon(
                        Icons.health_and_safety_rounded,
                        size: 68,
                        color: _primary,
                      ),
                    ),
                    SizedBox(height: 16),
                    Text(
                      _isCareMate
                          ? LifeMateRuntimeLocale.select(
                              fa: LifeMateRuntimeLocale.select(
                                fa: 'همراه مطمئن مراقبت از خانواده',
                                en: "Reliable family care companion",
                              ),
                              en: "Reliable family care companion",
                            )
                          : LifeMateRuntimeLocale.select(
                              fa: LifeMateRuntimeLocale.select(
                                fa: 'همراه ساده و آرام برنامه درمان',
                                en: "A simple and calm companion to the treatment program",
                              ),
                              en: "A simple and calm companion to the treatment program",
                            ),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Color(0xFF33416E),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 22),
                    Container(
                      padding: EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: _primary.withValues(alpha: 0.10),
                            blurRadius: 28,
                            offset: Offset(0, 14),
                          ),
                        ],
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _ModeSelector(
                              mode: _mode,
                              primary: _primary,
                              onChanged: _changeMode,
                            ),
                            SizedBox(height: 22),
                            Text(
                              isSignUp
                                  ? LifeMateRuntimeLocale.select(
                                      fa: LifeMateRuntimeLocale.select(
                                        fa: 'ساخت حساب جدید',
                                        en: "Create a new account",
                                      ),
                                      en: "Create a new account",
                                    )
                                  : LifeMateRuntimeLocale.select(
                                      fa: LifeMateRuntimeLocale.select(
                                        fa: 'خوش آمدید',
                                        en: "welcome",
                                      ),
                                      en: "welcome",
                                    ),
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF283054),
                                  ),
                            ),
                            SizedBox(height: 18),
                            if (LifeMateFeatureFlags.googleAuthEnabled) ...[
                              OutlinedButton.icon(
                                key: ValueKey<String>('auth-google'),
                                onPressed: _busy ? null : _signInWithGoogle,
                                icon: Text(
                                  'G',
                                  style: TextStyle(
                                    color: Color(0xFF4285F4),
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                label: Text(
                                  LifeMateRuntimeLocale.select(
                                    fa: LifeMateRuntimeLocale.select(
                                      fa: 'ادامه با حساب گوگل',
                                      en: "Continue with Google account",
                                    ),
                                    en: "Continue with Google account",
                                  ),
                                ),
                              ),
                              Padding(
                                padding: EdgeInsets.symmetric(vertical: 14),
                                child: Row(
                                  children: [
                                    Expanded(child: Divider()),
                                    Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 10,
                                      ),
                                      child: Text(
                                        LifeMateRuntimeLocale.select(
                                          fa: LifeMateRuntimeLocale.select(
                                            fa: 'یا با ایمیل',
                                            en: "or by email",
                                          ),
                                          en: "or by email",
                                        ),
                                      ),
                                    ),
                                    Expanded(child: Divider()),
                                  ],
                                ),
                              ),
                            ],
                            if (isSignUp) ...[
                              _AuthTextField(
                                controller: _displayName,
                                label: LifeMateRuntimeLocale.select(
                                  fa: LifeMateRuntimeLocale.select(
                                    fa: 'نام و نام خانوادگی',
                                    en: "Name and surname",
                                  ),
                                  en: "Name and surname",
                                ),
                                icon: Icons.person_outline_rounded,
                                textInputAction: TextInputAction.next,
                                autofillHints: [AutofillHints.name],
                                validator: (value) =>
                                    (value?.trim().length ?? 0) >= 2
                                    ? null
                                    : LifeMateRuntimeLocale.select(
                                        fa: LifeMateRuntimeLocale.select(
                                          fa: 'نام خود را وارد کنید.',
                                          en: "Enter your name.",
                                        ),
                                        en: "Enter your name.",
                                      ),
                              ),
                              SizedBox(height: 14),
                            ],
                            _AuthTextField(
                              controller: _email,
                              label: LifeMateRuntimeLocale.select(
                                fa: LifeMateRuntimeLocale.select(
                                  fa: 'ایمیل',
                                  en: "Email",
                                ),
                                en: "Email",
                              ),
                              icon: Icons.alternate_email_rounded,
                              keyboardType: TextInputType.emailAddress,
                              textDirection: TextDirection.ltr,
                              textInputAction: TextInputAction.next,
                              autofillHints: [AutofillHints.email],
                              validator: (value) =>
                                  _looksLikeEmail(value?.trim() ?? '')
                                  ? null
                                  : LifeMateRuntimeLocale.select(
                                      fa: LifeMateRuntimeLocale.select(
                                        fa: 'ایمیل معتبر وارد کنید.',
                                        en: "Enter a valid email.",
                                      ),
                                      en: "Enter a valid email.",
                                    ),
                            ),
                            SizedBox(height: 14),
                            _AuthTextField(
                              controller: _password,
                              label: LifeMateRuntimeLocale.select(
                                fa: LifeMateRuntimeLocale.select(
                                  fa: 'رمز عبور',
                                  en: "password",
                                ),
                                en: "password",
                              ),
                              icon: Icons.lock_outline_rounded,
                              obscureText: _obscure,
                              textDirection: TextDirection.ltr,
                              textInputAction: isSignUp
                                  ? TextInputAction.next
                                  : TextInputAction.done,
                              autofillHints: [
                                isSignUp
                                    ? AutofillHints.newPassword
                                    : AutofillHints.password,
                              ],
                              suffix: IconButton(
                                tooltip: _obscure
                                    ? LifeMateRuntimeLocale.select(
                                        fa: LifeMateRuntimeLocale.select(
                                          fa: 'نمایش رمز عبور',
                                          en: "Show password",
                                        ),
                                        en: "Show password",
                                      )
                                    : LifeMateRuntimeLocale.select(
                                        fa: LifeMateRuntimeLocale.select(
                                          fa: 'پنهان‌کردن رمز عبور',
                                          en: "Hide password",
                                        ),
                                        en: "Hide password",
                                      ),
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                                icon: Icon(
                                  _obscure
                                      ? Icons.visibility_rounded
                                      : Icons.visibility_off_rounded,
                                ),
                              ),
                              validator: isSignUp
                                  ? _validateNewPassword
                                  : (value) => (value?.isNotEmpty ?? false)
                                        ? null
                                        : LifeMateRuntimeLocale.select(
                                            fa: LifeMateRuntimeLocale.select(
                                              fa: 'رمز عبور را وارد کنید.',
                                              en: "Enter the password.",
                                            ),
                                            en: "Enter the password.",
                                          ),
                              onSubmitted: (_) {
                                if (!isSignUp) _submit();
                              },
                            ),
                            if (isSignUp) ...[
                              SizedBox(height: 14),
                              _AuthTextField(
                                controller: _confirmPassword,
                                label: LifeMateRuntimeLocale.select(
                                  fa: LifeMateRuntimeLocale.select(
                                    fa: 'تکرار رمز عبور',
                                    en: "Repeat password",
                                  ),
                                  en: "Repeat password",
                                ),
                                icon: Icons.lock_reset_rounded,
                                obscureText: _obscureConfirm,
                                textDirection: TextDirection.ltr,
                                textInputAction: TextInputAction.done,
                                autofillHints: [AutofillHints.newPassword],
                                suffix: IconButton(
                                  tooltip: _obscureConfirm
                                      ? LifeMateRuntimeLocale.select(
                                          fa: LifeMateRuntimeLocale.select(
                                            fa: 'نمایش تکرار رمز',
                                            en: "Show password repetition",
                                          ),
                                          en: "Show password repetition",
                                        )
                                      : LifeMateRuntimeLocale.select(
                                          fa: LifeMateRuntimeLocale.select(
                                            fa: 'پنهان‌کردن تکرار رمز',
                                            en: "Hide password repetition",
                                          ),
                                          en: "Hide password repetition",
                                        ),
                                  onPressed: () => setState(
                                    () => _obscureConfirm = !_obscureConfirm,
                                  ),
                                  icon: Icon(
                                    _obscureConfirm
                                        ? Icons.visibility_rounded
                                        : Icons.visibility_off_rounded,
                                  ),
                                ),
                                validator: (value) => value == _password.text
                                    ? null
                                    : LifeMateRuntimeLocale.select(
                                        fa: LifeMateRuntimeLocale.select(
                                          fa: 'تکرار رمز عبور یکسان نیست.',
                                          en: "Repeating the password is not the same.",
                                        ),
                                        en: "Repeating the password is not the same.",
                                      ),
                                onSubmitted: (_) => _submit(),
                              ),
                            ] else
                              Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: TextButton(
                                  onPressed: _busy ? null : _sendPasswordReset,
                                  child: Text(
                                    LifeMateRuntimeLocale.select(
                                      fa: LifeMateRuntimeLocale.select(
                                        fa: 'رمز عبور را فراموش کرده‌ام',
                                        en: "I forgot the password",
                                      ),
                                      en: "I forgot the password",
                                    ),
                                  ),
                                ),
                              ),
                            if (_error != null) ...[
                              SizedBox(height: 8),
                              _MessageBanner(
                                message: _error!,
                                color: Theme.of(context).colorScheme.error,
                                icon: Icons.error_outline_rounded,
                              ),
                            ],
                            if (_success != null) ...[
                              SizedBox(height: 8),
                              _MessageBanner(
                                message: _success!,
                                color: Color(0xFF16845B),
                                icon: Icons.mark_email_read_outlined,
                              ),
                            ],
                            SizedBox(height: 18),
                            SizedBox(
                              height: 54,
                              child: FilledButton(
                                onPressed: _busy ? null : _submit,
                                style: FilledButton.styleFrom(
                                  backgroundColor: _primary,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(17),
                                  ),
                                ),
                                child: _busy
                                    ? SizedBox.square(
                                        dimension: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Text(
                                        isSignUp
                                            ? LifeMateRuntimeLocale.select(
                                                fa: LifeMateRuntimeLocale.select(
                                                  fa: 'ساخت حساب امن',
                                                  en: "Create a secure account",
                                                ),
                                                en: "Create a secure account",
                                              )
                                            : LifeMateRuntimeLocale.select(
                                                fa: LifeMateRuntimeLocale.select(
                                                  fa: 'ورود امن',
                                                  en: "Secure login",
                                                ),
                                                en: "Secure login",
                                              ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static bool _looksLikeEmail(String value) {
    final at = value.indexOf('@');
    final dot = value.lastIndexOf('.');
    return at > 0 && dot > at + 1 && dot < value.length - 1;
  }

  static String? _validateNewPassword(String? value) {
    final password = value ?? '';
    if (password.length < 10) {
      return LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'رمز عبور باید حداقل ۱۰ کاراکتر باشد.',
          en: "Password must be at least 10 characters long.",
        ),
        en: "Password must be at least 10 characters long.",
      );
    }
    if (!RegExp(r'[A-Za-z]').hasMatch(password) ||
        !RegExp(r'[0-9]').hasMatch(password)) {
      return LifeMateRuntimeLocale.select(
        fa: 'رمز عبور باید شامل حرف و عدد باشد.',
        en: 'Password must contain both letters and numbers.',
      );
    }
    return null;
  }

  static String _friendlyAuthError(AuthException error) {
    final message = error.message.toLowerCase();
    if (message.contains('invalid login credentials') ||
        message.contains('user not found')) {
      return LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'ایمیل یا رمز عبور صحیح نیست.',
          en: "The email or password is incorrect.",
        ),
        en: "The email or password is incorrect.",
      );
    }
    if (message.contains('email not confirmed')) {
      return LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'ابتدا ایمیل خود را تأیید کنید.',
          en: "First, verify your email.",
        ),
        en: "First, verify your email.",
      );
    }
    if (message.contains('rate limit')) {
      return LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'تعداد درخواست‌ها زیاد است؛ کمی بعد دوباره تلاش کنید.',
          en: "The number of requests is high; Try again later.",
        ),
        en: "The number of requests is high; Try again later.",
      );
    }
    if (message.contains('password')) {
      return LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'رمز عبور شرایط امنیتی لازم را ندارد.',
          en: "The password does not meet the security requirements.",
        ),
        en: "The password does not meet the security requirements.",
      );
    }
    return LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'عملیات حساب انجام نشد. اطلاعات را بررسی و دوباره تلاش کنید.',
        en: "The account operation was not completed. Check the information and try again.",
      ),
      en: "The account operation was not completed. Check the information and try again.",
    );
  }
}

class _PasswordRecoveryScreen extends StatefulWidget {
  const _PasswordRecoveryScreen({
    required this.appName,
    required this.logoAssetPath,
    required this.supabase,
    required this.onCancelled,
  });

  final String appName;
  final String logoAssetPath;
  final SupabaseClient supabase;
  final Future<void> Function() onCancelled;

  @override
  State<_PasswordRecoveryScreen> createState() =>
      _PasswordRecoveryScreenState();
}

class _PasswordRecoveryScreenState extends State<_PasswordRecoveryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.supabase.auth
          .updateUser(UserAttributes(password: _password.text))
          .timeout(const Duration(seconds: 20));
      await widget.supabase.auth.signOut();
    } on TimeoutException {
      if (mounted)
        setState(
          () => _error = LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'پاسخی دریافت نشد. دوباره تلاش کنید.',
              en: "No response received. Try again.",
            ),
            en: "No response received. Try again.",
          ),
        );
    } on AuthException {
      if (mounted) {
        setState(
          () => _error = LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'تغییر رمز انجام نشد. یک لینک بازیابی جدید بگیرید.',
              en: "The password was not changed. Get a new recovery link.",
            ),
            en: "The password was not changed. Get a new recovery link.",
          ),
        );
      }
    } catch (_) {
      if (mounted)
        setState(
          () => _error = LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'ارتباط با سرور برقرار نشد.',
              en: "The connection with the server could not be established.",
            ),
            en: "The connection with the server could not be established.",
          ),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final care = widget.appName.toLowerCase().contains('care');
    final primary = care ? const Color(0xFF4A90E2) : const Color(0xFF10B981);
    return Scaffold(
      backgroundColor: care ? Color(0xFFE2EFFF) : Color(0xFFF1FAF5),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 420),
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Image.asset(widget.logoAssetPath, height: 64),
                        SizedBox(height: 18),
                        Text(
                          LifeMateRuntimeLocale.select(
                            fa: LifeMateRuntimeLocale.select(
                              fa: 'انتخاب رمز عبور جدید',
                              en: "Choose a new password",
                            ),
                            en: "Choose a new password",
                          ),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 18),
                        _AuthTextField(
                          controller: _password,
                          label: LifeMateRuntimeLocale.select(
                            fa: LifeMateRuntimeLocale.select(
                              fa: 'رمز عبور جدید',
                              en: "New password",
                            ),
                            en: "New password",
                          ),
                          icon: Icons.lock_reset_rounded,
                          obscureText: _obscure,
                          textDirection: TextDirection.ltr,
                          suffix: IconButton(
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_rounded
                                  : Icons.visibility_off_rounded,
                            ),
                          ),
                          validator: _EmailPasswordAuthScreenState
                              ._validateNewPassword,
                        ),
                        SizedBox(height: 14),
                        _AuthTextField(
                          controller: _confirm,
                          label: LifeMateRuntimeLocale.select(
                            fa: LifeMateRuntimeLocale.select(
                              fa: 'تکرار رمز عبور',
                              en: "Repeat password",
                            ),
                            en: "Repeat password",
                          ),
                          icon: Icons.lock_outline_rounded,
                          obscureText: _obscure,
                          textDirection: TextDirection.ltr,
                          validator: (value) => value == _password.text
                              ? null
                              : LifeMateRuntimeLocale.select(
                                  fa: LifeMateRuntimeLocale.select(
                                    fa: 'تکرار رمز عبور یکسان نیست.',
                                    en: "Repeating the password is not the same.",
                                  ),
                                  en: "Repeating the password is not the same.",
                                ),
                        ),
                        if (_error != null) ...[
                          SizedBox(height: 12),
                          _MessageBanner(
                            message: _error!,
                            color: Theme.of(context).colorScheme.error,
                            icon: Icons.error_outline_rounded,
                          ),
                        ],
                        SizedBox(height: 18),
                        FilledButton(
                          onPressed: _busy ? null : _save,
                          style: FilledButton.styleFrom(
                            backgroundColor: primary,
                          ),
                          child: _busy
                              ? SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  LifeMateRuntimeLocale.select(
                                    fa: LifeMateRuntimeLocale.select(
                                      fa: 'ثبت رمز جدید',
                                      en: "Register a new password",
                                    ),
                                    en: "Register a new password",
                                  ),
                                ),
                        ),
                        TextButton(
                          onPressed: _busy ? null : widget.onCancelled,
                          child: Text(
                            LifeMateRuntimeLocale.select(
                              fa: LifeMateRuntimeLocale.select(
                                fa: 'انصراف و بازگشت به ورود',
                                en: "Cancel and return to login",
                              ),
                              en: "Cancel and return to login",
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeSelector extends StatelessWidget {
  const _ModeSelector({
    required this.mode,
    required this.primary,
    required this.onChanged,
  });

  final _AuthMode mode;
  final Color primary;
  final ValueChanged<_AuthMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<_AuthMode>(
      segments: [
        ButtonSegment(
          value: _AuthMode.signIn,
          label: Text(
            LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(fa: 'ورود', en: "login"),
              en: "login",
            ),
          ),
        ),
        ButtonSegment(
          value: _AuthMode.signUp,
          label: Text(
            LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'ثبت‌نام',
                en: "registration",
              ),
              en: "registration",
            ),
          ),
        ),
      ],
      selected: {_AuthMode.values[mode.index]},
      onSelectionChanged: (selection) => onChanged(selection.single),
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? primary.withValues(alpha: 0.12)
              : Colors.transparent,
        ),
      ),
    );
  }
}

class _AuthTextField extends StatelessWidget {
  const _AuthTextField({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType,
    this.textDirection,
    this.textInputAction,
    this.autofillHints,
    this.obscureText = false,
    this.suffix,
    this.validator,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  final TextDirection? textDirection;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final bool obscureText;
  final Widget? suffix;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textDirection: textDirection,
      textInputAction: textInputAction,
      autofillHints: autofillHints,
      obscureText: obscureText,
      validator: validator,
      onFieldSubmitted: onSubmitted,
      autocorrect: false,
      enableSuggestions: !obscureText,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        suffixIcon: suffix,
        filled: true,
        fillColor: const Color(0xFFF7F9FC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _MessageBanner extends StatelessWidget {
  const _MessageBanner({
    required this.message,
    required this.color,
    required this.icon,
  });

  final String message;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: color.withValues(alpha: 0.16)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 9),
            Expanded(
              child: Text(message, style: TextStyle(color: color)),
            ),
          ],
        ),
      ),
    );
  }
}

class _BlockingState extends StatelessWidget {
  const _BlockingState({
    required this.appName,
    required this.icon,
    required this.title,
    required this.message,
    this.logoAssetPath,
    this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  final String appName;
  final String? logoAssetPath;
  final IconData icon;
  final String title;
  final String message;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final care = appName.toLowerCase().contains('care');
    final primary = care ? const Color(0xFF4A90E2) : const Color(0xFF10B981);
    return Scaffold(
      backgroundColor: care ? const Color(0xFFE2EFFF) : const Color(0xFFF1FAF5),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (logoAssetPath != null) ...[
                        Image.asset(
                          logoAssetPath!,
                          height: 68,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                        const SizedBox(height: 18),
                      ],
                      Icon(icon, size: 44, color: primary),
                      const SizedBox(height: 18),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(message, textAlign: TextAlign.center),
                      if (primaryLabel != null && onPrimary != null) ...[
                        const SizedBox(height: 22),
                        FilledButton(
                          onPressed: onPrimary,
                          style: FilledButton.styleFrom(
                            backgroundColor: primary,
                          ),
                          child: Text(primaryLabel!),
                        ),
                      ],
                      if (secondaryLabel != null && onSecondary != null)
                        TextButton(
                          onPressed: onSecondary,
                          child: Text(secondaryLabel!),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
