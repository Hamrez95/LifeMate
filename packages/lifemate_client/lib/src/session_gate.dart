import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config.dart';
import 'lifemate_api_client.dart';
import 'lifemate_auth.dart';

typedef AuthenticatedBuilder = Widget Function(
  BuildContext context,
  LifeMateApiClient apiClient,
);

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
  final AuthenticatedBuilder authenticatedBuilder;

  @override
  State<LifeMateSessionGate> createState() => _LifeMateSessionGateState();
}

class _LifeMateSessionGateState extends State<LifeMateSessionGate> {
  late final SupabaseClient _supabase;
  late final LifeMateApiClient _api;
  late final StreamSubscription<AuthState> _authSubscription;
  Session? _session;
  Future<void>? _bootstrap;
  Object? _authStreamError;

  @override
  void initState() {
    super.initState();
    _supabase = Supabase.instance.client;
    _api = LifeMateApiClient(
      baseUri: widget.config.apiBaseUri,
      accessToken: () => _supabase.auth.currentSession?.accessToken,
    );
    _session = _supabase.auth.currentSession;
    if (_session != null) _bootstrap = _bootstrapUser(_session!);
    _authSubscription = _supabase.auth.onAuthStateChange.listen(
      (state) {
        if (!mounted) return;
        setState(() {
          _authStreamError = null;
          _session = state.session;
          _bootstrap =
              state.session == null ? null : _bootstrapUser(state.session!);
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
    await _api.bootstrapUser(
      displayName: displayName ?? user.email?.split('@').first,
      email: user.email,
    );
  }

  void _retryBootstrap() {
    final session = _session;
    if (session == null) return;
    setState(() => _bootstrap = _bootstrapUser(session));
  }

  @override
  void dispose() {
    _authSubscription.cancel();
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
        title: 'ارتباط امن با حساب کاربری قطع شد',
        message: 'اتصال اینترنت را بررسی کنید و دوباره تلاش کنید.',
        primaryLabel: 'تلاش دوباره',
        onPrimary: () => setState(() => _authStreamError = null),
      );
    }

    if (_session == null) {
      return _AuthScreen(
        appName: widget.appName,
        logoAssetPath: widget.logoAssetPath,
        supabase: _supabase,
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
            title: 'در حال آماده‌سازی حساب',
            message: 'اطلاعات شما به‌صورت امن همگام می‌شود.',
          );
        }
        if (snapshot.hasError) {
          final expired = snapshot.error is LifeMateApiException &&
              (snapshot.error! as LifeMateApiException).isUnauthorized;
          return _BlockingState(
            appName: widget.appName,
            logoAssetPath: widget.logoAssetPath,
            icon: Icons.sync_problem_rounded,
            title: expired ? 'نشست شما منقضی شده است' : 'همگام‌سازی انجام نشد',
            message: expired
                ? 'برای ادامه دوباره وارد حساب شوید.'
                : 'داده‌ای تغییر نکرده است. اتصال را بررسی و دوباره تلاش کنید.',
            primaryLabel: expired ? 'خروج و ورود دوباره' : 'تلاش دوباره',
            onPrimary:
                expired ? () => _supabase.auth.signOut() : _retryBootstrap,
            secondaryLabel: expired ? null : 'خروج از حساب',
            onSecondary: expired ? null : () => _supabase.auth.signOut(),
          );
        }
        return widget.authenticatedBuilder(context, _api);
      },
    );
  }
}

enum _AuthMode { signIn, signUp }

class _AuthScreen extends StatefulWidget {
  const _AuthScreen({
    required this.appName,
    required this.logoAssetPath,
    required this.supabase,
  });

  final String appName;
  final String logoAssetPath;
  final SupabaseClient supabase;

  @override
  State<_AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<_AuthScreen> {
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

  Color get _secondary =>
      _isCareMate ? const Color(0xFF8DCDF8) : const Color(0xFF77D9B4);

  Color get _background =>
      _isCareMate ? const Color(0xFFE2EFFF) : const Color(0xFFF1FAF5);

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
      _success = null;
    });
    try {
      if (_mode == _AuthMode.signIn) {
        await widget.supabase.auth.signInWithPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
      } else {
        final response = await widget.supabase.auth.signUp(
          email: _email.text.trim(),
          password: _password.text,
          emailRedirectTo: LifeMateAuth.callbackUrlForApp(widget.appName),
          data: {'display_name': _displayName.text.trim()},
        );
        if (!mounted) return;
        if (response.session == null) {
          setState(() {
            _success =
                'حساب ساخته شد. ایمیل تأیید را بررسی کنید و سپس وارد شوید.';
            _mode = _AuthMode.signIn;
            _password.clear();
            _confirmPassword.clear();
          });
        }
      }
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = _friendlyAuthError(error));
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'ارتباط با سرور برقرار نشد. دوباره تلاش کنید.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _success = null;
    });
    try {
      final launched = await LifeMateAuth.signInWithGoogle(
        appName: widget.appName,
      );
      if (!launched && mounted) {
        setState(() => _error = 'صفحه ورود گوگل باز نشد. دوباره تلاش کنید.');
      }
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = _friendlyAuthError(error));
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'ورود با گوگل انجام نشد. دوباره تلاش کنید.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendPasswordReset() async {
    final email = _email.text.trim();
    if (!_looksLikeEmail(email)) {
      setState(() {
        _error = 'ابتدا ایمیل معتبر خود را در کادر ایمیل وارد کنید.';
        _success = null;
      });
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _success = null;
    });
    try {
      await widget.supabase.auth.resetPasswordForEmail(
        email,
        redirectTo: LifeMateAuth.callbackUrlForApp(widget.appName),
      );
      if (mounted) {
        setState(() {
          _success = 'لینک بازیابی رمز برای شما ارسال شد.';
        });
      }
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = _friendlyAuthError(error));
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'ارسال لینک بازیابی انجام نشد.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _changeMode(_AuthMode mode) {
    if (_busy || _mode == mode) return;
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
      body: Stack(
        children: [
          Positioned(
            top: -95,
            right: -70,
            child: _PastelOrb(size: 230, color: _secondary.withOpacity(0.32)),
          ),
          Positioned(
            bottom: -110,
            left: -85,
            child: _PastelOrb(size: 250, color: _primary.withOpacity(0.13)),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 24, 22, 32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    children: [
                      Hero(
                        tag: '${widget.appName}-auth-logo',
                        child: Image.asset(
                          widget.logoAssetPath,
                          height: 82,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => Icon(
                            Icons.health_and_safety_rounded,
                            size: 68,
                            color: _primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _isCareMate
                            ? 'همراه مطمئن مراقبت از خانواده'
                            : 'همراه ساده و آرام برنامه درمان',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: const Color(0xFF33416E),
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 22),
                      Container(
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.94),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.85),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _primary.withOpacity(0.10),
                              blurRadius: 28,
                              offset: const Offset(0, 14),
                            ),
                            BoxShadow(
                              color: Colors.white.withOpacity(0.8),
                              blurRadius: 12,
                              offset: const Offset(-6, -6),
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
                              const SizedBox(height: 24),
                              Text(
                                isSignUp ? 'ساخت حساب جدید' : 'خوش آمدید',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w900,
                                      color: const Color(0xFF283054),
                                    ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                isSignUp
                                    ? 'برای شروع، اطلاعات اصلی حساب را وارد کنید.'
                                    : 'برای ادامه وارد حساب LifeMate خود شوید.',
                                style: const TextStyle(
                                  color: Color(0xFF71819C),
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 22),
                              OutlinedButton.icon(
                                key: const ValueKey<String>('auth-google'),
                                onPressed: _busy ? null : _signInWithGoogle,
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(52),
                                  foregroundColor: const Color(0xFF283054),
                                  side: const BorderSide(
                                    color: Color(0xFFDCE3EB),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(17),
                                  ),
                                ),
                                icon: Container(
                                  width: 26,
                                  height: 26,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: const Color(0xFFE4E8ED),
                                    ),
                                  ),
                                  child: const Text(
                                    'G',
                                    style: TextStyle(
                                      color: Color(0xFF4285F4),
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                label: const Text(
                                  'ادامه با حساب گوگل',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Row(
                                  children: [
                                    Expanded(child: Divider()),
                                    Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 10),
                                      child: Text(
                                        'یا با ایمیل',
                                        style: TextStyle(
                                          color: Color(0xFF8A96A8),
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                    Expanded(child: Divider()),
                                  ],
                                ),
                              ),
                              if (isSignUp) ...[
                                _AuthTextField(
                                  controller: _displayName,
                                  label: 'نام و نام خانوادگی',
                                  icon: Icons.person_outline_rounded,
                                  textInputAction: TextInputAction.next,
                                  autofillHints: const [AutofillHints.name],
                                  validator: (value) =>
                                      (value?.trim().length ?? 0) >= 2
                                          ? null
                                          : 'نام خود را وارد کنید.',
                                ),
                                const SizedBox(height: 14),
                              ],
                              _AuthTextField(
                                controller: _email,
                                label: 'ایمیل',
                                icon: Icons.alternate_email_rounded,
                                keyboardType: TextInputType.emailAddress,
                                textDirection: TextDirection.ltr,
                                textInputAction: TextInputAction.next,
                                autofillHints: const [AutofillHints.email],
                                validator: (value) =>
                                    _looksLikeEmail(value?.trim() ?? '')
                                        ? null
                                        : 'ایمیل معتبر وارد کنید.',
                              ),
                              const SizedBox(height: 14),
                              _AuthTextField(
                                controller: _password,
                                label: 'رمز عبور',
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
                                      ? 'نمایش رمز عبور'
                                      : 'پنهان‌کردن رمز عبور',
                                  onPressed: () =>
                                      setState(() => _obscure = !_obscure),
                                  icon: Icon(
                                    _obscure
                                        ? Icons.visibility_rounded
                                        : Icons.visibility_off_rounded,
                                  ),
                                ),
                                validator: (value) => (value?.length ?? 0) >= 8
                                    ? null
                                    : 'رمز عبور باید حداقل ۸ کاراکتر باشد.',
                                onSubmitted: (_) {
                                  if (!isSignUp && !_busy) _submit();
                                },
                              ),
                              if (isSignUp) ...[
                                const SizedBox(height: 14),
                                _AuthTextField(
                                  controller: _confirmPassword,
                                  label: 'تکرار رمز عبور',
                                  icon: Icons.lock_reset_rounded,
                                  obscureText: _obscureConfirm,
                                  textDirection: TextDirection.ltr,
                                  textInputAction: TextInputAction.done,
                                  autofillHints: const [
                                    AutofillHints.newPassword,
                                  ],
                                  suffix: IconButton(
                                    tooltip: _obscureConfirm
                                        ? 'نمایش تکرار رمز'
                                        : 'پنهان‌کردن تکرار رمز',
                                    onPressed: () => setState(
                                      () => _obscureConfirm =
                                          !_obscureConfirm,
                                    ),
                                    icon: Icon(
                                      _obscureConfirm
                                          ? Icons.visibility_rounded
                                          : Icons.visibility_off_rounded,
                                    ),
                                  ),
                                  validator: (value) =>
                                      value == _password.text
                                          ? null
                                          : 'تکرار رمز عبور یکسان نیست.',
                                  onSubmitted: (_) {
                                    if (!_busy) _submit();
                                  },
                                ),
                              ] else
                                Align(
                                  alignment: AlignmentDirectional.centerStart,
                                  child: TextButton(
                                    onPressed:
                                        _busy ? null : _sendPasswordReset,
                                    child: const Text('رمز عبور را فراموش کرده‌ام'),
                                  ),
                                ),
                              if (_error != null) ...[
                                const SizedBox(height: 8),
                                _MessageBanner(
                                  message: _error!,
                                  icon: Icons.error_outline_rounded,
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ],
                              if (_success != null) ...[
                                const SizedBox(height: 8),
                                _MessageBanner(
                                  message: _success!,
                                  icon: Icons.mark_email_read_outlined,
                                  color: const Color(0xFF16845B),
                                ),
                              ],
                              const SizedBox(height: 20),
                              SizedBox(
                                height: 54,
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: _primary,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(17),
                                    ),
                                  ),
                                  onPressed: _busy ? null : _submit,
                                  child: _busy
                                      ? const SizedBox.square(
                                          dimension: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : Text(
                                          isSignUp
                                              ? 'ساخت حساب امن'
                                              : 'ورود امن',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.shield_outlined,
                                    size: 16,
                                    color: _primary,
                                  ),
                                  const SizedBox(width: 6),
                                  const Flexible(
                                    child: Text(
                                      'اطلاعات سلامت فقط در محدوده دسترسی مجاز نمایش داده می‌شود.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Color(0xFF7A879B),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.72),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Text(
                          'نسخه آزمایشی LifeMate',
                          style: TextStyle(
                            color: Color(0xFF71819C),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static bool _looksLikeEmail(String value) {
    final at = value.indexOf('@');
    final dot = value.lastIndexOf('.');
    return at > 0 && dot > at + 1 && dot < value.length - 1;
  }

  static String _friendlyAuthError(AuthException error) {
    final message = error.message.toLowerCase();
    if (message.contains('invalid login credentials')) {
      return 'ایمیل یا رمز عبور درست نیست.';
    }
    if (message.contains('email not confirmed')) {
      return 'ابتدا ایمیل خود را تأیید کنید.';
    }
    if (message.contains('user already registered')) {
      return 'این ایمیل قبلاً ثبت شده است؛ وارد حساب شوید.';
    }
    if (message.contains('password')) {
      return 'رمز عبور شرایط امنیتی لازم را ندارد.';
    }
    if (message.contains('provider') && message.contains('enabled')) {
      return 'ورود با گوگل هنوز برای این محیط فعال نشده است.';
    }
    if (message.contains('rate limit')) {
      return 'تعداد درخواست‌ها زیاد بوده است؛ کمی بعد دوباره تلاش کنید.';
    }
    return 'عملیات حساب انجام نشد. اطلاعات را بررسی و دوباره تلاش کنید.';
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
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F4F8),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ModeButton(
              label: 'ورود',
              selected: mode == _AuthMode.signIn,
              primary: primary,
              onTap: () => onChanged(_AuthMode.signIn),
            ),
          ),
          Expanded(
            child: _ModeButton(
              label: 'ثبت‌نام',
              selected: mode == _AuthMode.signUp,
              primary: primary,
              onTap: () => onChanged(_AuthMode.signUp),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.label,
    required this.selected,
    required this.primary,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color primary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: primary.withOpacity(0.10),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: selected ? primary : const Color(0xFF7A879B),
              fontWeight: FontWeight.w800,
            ),
          ),
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
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: const BorderSide(color: Color(0xFFE8EDF3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.primary,
            width: 1.5,
          ),
        ),
      ),
    );
  }
}

class _MessageBanner extends StatelessWidget {
  const _MessageBanner({
    required this.message,
    required this.icon,
    required this.color,
  });

  final String message;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: color.withOpacity(0.12)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: color, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PastelOrb extends StatelessWidget {
  const _PastelOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

class ConfigurationRequiredScreen extends StatelessWidget {
  const ConfigurationRequiredScreen({
    required this.appName,
    required this.missingValues,
    super.key,
  });

  final String appName;
  final List<String> missingValues;

  @override
  Widget build(BuildContext context) => _BlockingState(
        appName: appName,
        icon: Icons.settings_suggest_rounded,
        title: '$appName هنوز برای این محیط تنظیم نشده است',
        message:
            'مقادیر build-time زیر لازم‌اند:\n${missingValues.join(', ')}',
      );
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
    final careMate = appName.toLowerCase().contains('care');
    final primary =
        careMate ? const Color(0xFF4A90E2) : const Color(0xFF10B981);
    final background =
        careMate ? const Color(0xFFE2EFFF) : const Color(0xFFF1FAF5);

    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.94),
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: primary.withOpacity(0.1),
                      blurRadius: 28,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (logoAssetPath != null) ...[
                      Image.asset(
                        logoAssetPath!,
                        height: 68,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                      const SizedBox(height: 18),
                    ],
                    Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: primary.withOpacity(0.09),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, size: 44, color: primary),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF283054),
                          ),
                    ),
                    const SizedBox(height: 10),
                    Text(message, textAlign: TextAlign.center),
                    if (primaryLabel != null && onPrimary != null) ...[
                      const SizedBox(height: 24),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: onPrimary,
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
    );
  }
}
