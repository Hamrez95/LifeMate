import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config.dart';
import 'lifemate_api_client.dart';

typedef AuthenticatedBuilder = Widget Function(
  BuildContext context,
  LifeMateApiClient apiClient,
);

class LifeMateSessionGate extends StatefulWidget {
  const LifeMateSessionGate({
    required this.config,
    required this.appName,
    required this.authenticatedBuilder,
    super.key,
  });

  final AppConfig config;
  final String appName;
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
    final rawName = user.userMetadata?['display_name']?.toString().trim();
    await _api.bootstrapUser(
      displayName: rawName == null || rawName.isEmpty
          ? user.email?.split('@').first
          : rawName,
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
        icon: Icons.cloud_off_rounded,
        title: 'ارتباط امن با حساب کاربری قطع شد',
        message: 'اتصال اینترنت را بررسی کنید و دوباره تلاش کنید.',
        primaryLabel: 'تلاش دوباره',
        onPrimary: () => setState(() => _authStreamError = null),
      );
    }

    if (_session == null) {
      return _SignInScreen(appName: widget.appName, supabase: _supabase);
    }

    return FutureBuilder<void>(
      future: _bootstrap,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _BlockingState(
            icon: Icons.health_and_safety_rounded,
            title: 'در حال آماده‌سازی حساب',
            message: 'اطلاعات درمانی شما به‌صورت امن همگام می‌شود.',
          );
        }
        if (snapshot.hasError) {
          final expired = snapshot.error is LifeMateApiException &&
              (snapshot.error! as LifeMateApiException).isUnauthorized;
          return _BlockingState(
            icon: Icons.sync_problem_rounded,
            title: expired ? 'نشست شما منقضی شده است' : 'همگام‌سازی انجام نشد',
            message: expired
                ? 'برای ادامه دوباره وارد حساب شوید.'
                : 'داده‌ای تغییر نکرده است. اتصال را بررسی و دوباره تلاش کنید.',
            primaryLabel: expired ? 'خروج و ورود دوباره' : 'تلاش دوباره',
            onPrimary: expired
                ? () => _supabase.auth.signOut()
                : _retryBootstrap,
            secondaryLabel: expired ? null : 'خروج از حساب',
            onSecondary:
                expired ? null : () => _supabase.auth.signOut(),
          );
        }
        return widget.authenticatedBuilder(context, _api);
      },
    );
  }
}

class _SignInScreen extends StatefulWidget {
  const _SignInScreen({required this.appName, required this.supabase});

  final String appName;
  final SupabaseClient supabase;

  @override
  State<_SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<_SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.supabase.auth.signInWithPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'ارتباط با سرور برقرار نشد. دوباره تلاش کنید.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    Icon(
                      Icons.health_and_safety_rounded,
                      size: 72,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'ورود به ${widget.appName}',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'نسخه آزمایشی فقط برای کاربران دعوت‌شده فعال است.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      textDirection: TextDirection.ltr,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(
                        labelText: 'ایمیل',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        final email = value?.trim() ?? '';
                        return email.contains('@') ? null : 'ایمیل معتبر وارد کنید.';
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _password,
                      obscureText: _obscure,
                      textDirection: TextDirection.ltr,
                      autofillHints: const [AutofillHints.password],
                      decoration: InputDecoration(
                        labelText: 'رمز عبور',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _obscure = !_obscure),
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_rounded
                                : Icons.visibility_off_rounded,
                          ),
                        ),
                      ),
                      validator: (value) => (value?.length ?? 0) >= 8
                          ? null
                          : 'رمز عبور باید حداقل ۸ کاراکتر باشد.',
                      onFieldSubmitted: (_) => _busy ? null : _signIn(),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        onPressed: _busy ? null : _signIn,
                        child: _busy
                            ? const SizedBox.square(
                                dimension: 22,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('ورود امن'),
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
        icon: Icons.settings_suggest_rounded,
        title: '$appName هنوز برای این محیط تنظیم نشده است',
        message:
            'مقادیر build-time زیر لازم‌اند:\n${missingValues.join(', ')}',
      );
}

class _BlockingState extends StatelessWidget {
  const _BlockingState({
    required this.icon,
    required this.title,
    required this.message,
    this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 64, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 18),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 10),
                  Text(message, textAlign: TextAlign.center),
                  if (primaryLabel != null && onPrimary != null) ...[
                    const SizedBox(height: 24),
                    FilledButton(
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
    );
  }
}
