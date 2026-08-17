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
        setState(
          () => _error = LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'پاسخی دریافت نشد. دوباره تلاش کنید.',
              en: "No response received. Try again.",
            ),
            en: "No response received. Try again.",
          ),
        );
    } on AuthException catch (error) {
      if (mounted) {
        setState(
          () => _error = safeRecoveryAuthMessage(
            error.message,
            isPersian: LifeMateRuntimeLocale.isPersian,
          ),
        );
      }
    } catch (_) {
      if (mounted)
        setState(
          () => _error = LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'تغییر رمز عبور انجام نشد.',
              en: "Password change failed.",
            ),
            en: "Password change failed.",
          ),
        );
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
      textDirection: LifeMateRuntimeLocale.isPersian
          ? TextDirection.rtl
          : TextDirection.ltr,
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
                  padding: EdgeInsets.all(22),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: 450),
                    child: Container(
                      padding: EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(32),
                        boxShadow: [
                          BoxShadow(
                            color: brand.primary.withValues(alpha: 0.14),
                            blurRadius: 34,
                            offset: Offset(0, 18),
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
                            SizedBox(height: 16),
                            Text(
                              LifeMateRuntimeLocale.select(
                                fa: LifeMateRuntimeLocale.select(
                                  fa: 'ساخت رمز عبور جدید',
                                  en: "Create a new password",
                                ),
                                en: "Create a new password",
                              ),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: brand.ink,
                                fontSize: 25,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              LifeMateRuntimeLocale.select(
                                fa: LifeMateRuntimeLocale.select(
                                  fa: 'یک رمز قوی و متفاوت از رمزهای قبلی انتخاب کنید.',
                                  en: "Choose a strong password that is different from previous passwords.",
                                ),
                                en: "Choose a strong password that is different from previous passwords.",
                              ),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFF71809A),
                                height: 1.6,
                              ),
                            ),
                            SizedBox(height: 22),
                            _ExperienceTextField(
                              controller: _password,
                              label: LifeMateRuntimeLocale.select(
                                fa: LifeMateRuntimeLocale.select(
                                  fa: 'رمز عبور جدید',
                                  en: "New password",
                                ),
                                en: "New password",
                              ),
                              icon: Icons.lock_outline_rounded,
                              brand: brand,
                              obscureText: _obscure,
                              textDirection: TextDirection.ltr,
                              textInputAction: TextInputAction.next,
                              autofillHints: [AutofillHints.newPassword],
                              suffix: IconButton(
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                                icon: Icon(
                                  _obscure
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                ),
                              ),
                              validator: (value) =>
                                  LifeMatePasswordPolicy.validationMessage(
                                    value,
                                    isPersian: LifeMateRuntimeLocale.isPersian,
                                  ),
                            ),
                            SizedBox(height: 13),
                            _ExperienceTextField(
                              controller: _confirm,
                              label: LifeMateRuntimeLocale.select(
                                fa: LifeMateRuntimeLocale.select(
                                  fa: 'تکرار رمز عبور',
                                  en: "Repeat password",
                                ),
                                en: "Repeat password",
                              ),
                              icon: Icons.lock_reset_rounded,
                              brand: brand,
                              obscureText: _obscure,
                              textDirection: TextDirection.ltr,
                              textInputAction: TextInputAction.done,
                              autofillHints: [AutofillHints.newPassword],
                              validator: (value) => value == _password.text
                                  ? null
                                  : LifeMateRuntimeLocale.select(
                                      fa: LifeMateRuntimeLocale.select(
                                        fa: 'تکرار رمز یکسان نیست.',
                                        en: "Repeating the password is not the same.",
                                      ),
                                      en: "Repeating the password is not the same.",
                                    ),
                              onSubmitted: (_) => _savePassword(),
                            ),
                            if (_error != null) ...[
                              SizedBox(height: 12),
                              _StatusBanner(
                                message: _error!,
                                icon: Icons.error_outline_rounded,
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ],
                            SizedBox(height: 18),
                            _GradientActionButton(
                              brand: brand,
                              busy: _busy,
                              label: LifeMateRuntimeLocale.select(
                                fa: LifeMateRuntimeLocale.select(
                                  fa: 'ذخیره رمز جدید',
                                  en: "Save the new password",
                                ),
                                en: "Save the new password",
                              ),
                              icon: Icons.verified_user_rounded,
                              onPressed: _savePassword,
                            ),
                            SizedBox(height: 8),
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
          ],
        ),
      ),
    );
  }
}
