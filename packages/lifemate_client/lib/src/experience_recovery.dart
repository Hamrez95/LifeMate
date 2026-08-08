part of 'lifemate_experience_gate.dart';

class _PasswordRecoveryExperience extends StatefulWidget {
  const _PasswordRecoveryExperience({
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
  State<_PasswordRecoveryExperience> createState() =>
      _PasswordRecoveryExperienceState();
}

class _PasswordRecoveryExperienceState
    extends State<_PasswordRecoveryExperience> {
  static const _requestTimeout = Duration(seconds: 20);
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  _BrandPalette get _brand => _BrandPalette.forApp(widget.appName);

  Future<void> _savePassword() async {
    FocusScope.of(context).unfocus();
    if (_busy || !_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.supabase.auth
          .updateUser(UserAttributes(password: _password.text))
          .timeout(_requestTimeout);
      await widget.supabase.auth.signOut();
    } on TimeoutException {
      if (mounted)
        setState(() => _error = 'پاسخی دریافت نشد. دوباره تلاش کنید.');
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'تغییر رمز عبور انجام نشد.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brand = _brand;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: brand.background,
        body: Stack(
          children: [
            Positioned.fill(
              child: _AmbientBackdrop(progress: 0.18, brand: brand),
            ),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(22),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 450),
                    child: Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(32),
                        boxShadow: [
                          BoxShadow(
                            color: brand.primary.withValues(alpha: 0.14),
                            blurRadius: 34,
                            offset: const Offset(0, 18),
                          ),
                        ],
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Image.asset(
                              widget.logoAssetPath,
                              height: 82,
                              errorBuilder: (_, __, ___) => Icon(
                                Icons.lock_reset_rounded,
                                size: 66,
                                color: brand.primary,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'ساخت رمز عبور جدید',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: brand.ink,
                                fontSize: 25,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'یک رمز قوی و متفاوت از رمزهای قبلی انتخاب کنید.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFF71809A),
                                height: 1.6,
                              ),
                            ),
                            const SizedBox(height: 22),
                            _ExperienceTextField(
                              controller: _password,
                              label: 'رمز عبور جدید',
                              icon: Icons.lock_outline_rounded,
                              brand: brand,
                              obscureText: _obscure,
                              textDirection: TextDirection.ltr,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.newPassword],
                              suffix: IconButton(
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                                icon: Icon(
                                  _obscure
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                ),
                              ),
                              validator: (value) => (value?.length ?? 0) >= 8
                                  ? null
                                  : 'رمز باید حداقل ۸ کاراکتر باشد.',
                            ),
                            const SizedBox(height: 13),
                            _ExperienceTextField(
                              controller: _confirm,
                              label: 'تکرار رمز عبور',
                              icon: Icons.lock_reset_rounded,
                              brand: brand,
                              obscureText: _obscure,
                              textDirection: TextDirection.ltr,
                              textInputAction: TextInputAction.done,
                              autofillHints: const [AutofillHints.newPassword],
                              validator: (value) => value == _password.text
                                  ? null
                                  : 'تکرار رمز یکسان نیست.',
                              onSubmitted: (_) => _savePassword(),
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: 12),
                              _StatusBanner(
                                message: _error!,
                                icon: Icons.error_outline_rounded,
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ],
                            const SizedBox(height: 18),
                            _GradientActionButton(
                              brand: brand,
                              busy: _busy,
                              label: 'ذخیره رمز جدید',
                              icon: Icons.verified_user_rounded,
                              onPressed: _savePassword,
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: _busy ? null : widget.onCancelled,
                              child: const Text('انصراف و بازگشت به ورود'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
