part of 'lifemate_experience_gate.dart';

enum _AuthMode { signIn, signUp }

class _LifeMateAuthExperience extends StatefulWidget {
  const _LifeMateAuthExperience({
    required this.appName,
    required this.logoAssetPath,
    required this.supabase,
  });

  final String appName;
  final String logoAssetPath;
  final SupabaseClient supabase;

  @override
  State<_LifeMateAuthExperience> createState() =>
      _LifeMateAuthExperienceState();
}

class _LifeMateAuthExperienceState extends State<_LifeMateAuthExperience>
    with TickerProviderStateMixin {
  static const _requestTimeout = Duration(seconds: 20);

  final _formKey = GlobalKey<FormState>();
  final _displayName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();

  late final AnimationController _ambientController;
  late final AnimationController _entranceController;
  late final Animation<double> _entranceOpacity;
  late final Animation<Offset> _entranceOffset;

  _AuthMode _mode = _AuthMode.signIn;
  bool _busy = false;
  bool _obscure = true;
  bool _obscureConfirm = true;
  String? _error;
  String? _success;

  _BrandPalette get _brand => _BrandPalette.forApp(widget.appName);

  @override
  void initState() {
    super.initState();
    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    )..forward();
    _entranceOpacity = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0, 0.8, curve: Curves.easeOut),
    );
    _entranceOffset =
        Tween<Offset>(begin: const Offset(0, 0.055), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _entranceController,
            curve: Curves.easeOutCubic,
          ),
        );
  }

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
            _success = 'حساب ساخته شد. اکنون می‌توانید وارد شوید.';
            _mode = _AuthMode.signIn;
            _password.clear();
            _confirmPassword.clear();
          });
        }
      }
    } on TimeoutException {
      if (mounted) {
        setState(
          () => _error = 'پاسخی دریافت نشد. اتصال را بررسی و دوباره تلاش کنید.',
        );
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

  Future<void> _sendPasswordReset() async {
    final email = _email.text.trim();
    if (!_looksLikeEmail(email)) {
      setState(() {
        _error = 'ابتدا ایمیل معتبر خود را وارد کنید.';
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
          _success =
              'اگر حسابی با این ایمیل وجود داشته باشد، لینک بازیابی ارسال می‌شود.';
        });
      }
    } on TimeoutException {
      if (mounted) {
        setState(() => _error = 'پاسخی دریافت نشد. کمی بعد دوباره تلاش کنید.');
      }
    } on AuthException catch (error) {
      if (!mounted) return;
      if (error.message.toLowerCase().contains('rate limit')) {
        setState(
          () => _error = 'تعداد درخواست‌ها زیاد است؛ کمی بعد دوباره تلاش کنید.',
        );
      } else {
        setState(() {
          _success =
              'اگر حسابی با این ایمیل وجود داشته باشد، لینک بازیابی ارسال می‌شود.';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'ارسال درخواست بازیابی انجام نشد.');
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
        setState(() => _error = 'صفحه ورود گوگل باز نشد. دوباره تلاش کنید.');
      }
    } on TimeoutException {
      if (mounted) {
        setState(() => _error = 'درخواست ورود به پایان زمان مجاز رسید.');
      }
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = _friendlyAuthError(error));
    } catch (_) {
      if (mounted) setState(() => _error = 'ورود با گوگل انجام نشد.');
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
    _ambientController.dispose();
    _entranceController.dispose();
    _displayName.dispose();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
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
              child: AnimatedBuilder(
                animation: _ambientController,
                builder: (context, child) => _AmbientBackdrop(
                  progress: _ambientController.value,
                  brand: brand,
                ),
              ),
            ),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 470),
                    child: FadeTransition(
                      opacity: _entranceOpacity,
                      child: SlideTransition(
                        position: _entranceOffset,
                        child: AutofillGroup(
                          child: Column(
                            children: [
                              _AuthHero(
                                brand: brand,
                                logoAssetPath: widget.logoAssetPath,
                                mode: _mode,
                              ),
                              const SizedBox(height: 22),
                              _buildAuthCard(context, brand),
                            ],
                          ),
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

  Widget _buildAuthCard(BuildContext context, _BrandPalette brand) {
    final isSignUp = _mode == _AuthMode.signUp;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(34),
        border: Border.all(color: Colors.white.withValues(alpha: 0.94)),
        boxShadow: [
          BoxShadow(
            color: brand.primary.withValues(alpha: 0.14),
            blurRadius: 34,
            offset: const Offset(0, 18),
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.86),
            blurRadius: 14,
            offset: const Offset(-7, -7),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _AuthModeSelector(
              mode: _mode,
              brand: brand,
              enabled: !_busy,
              onChanged: _changeMode,
            ),
            const SizedBox(height: 22),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.035, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: Column(
                key: ValueKey(_mode),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (isSignUp) ...[
                    _ExperienceTextField(
                      key: const ValueKey('auth-display-name'),
                      controller: _displayName,
                      label: 'نام و نام خانوادگی',
                      icon: Icons.person_outline_rounded,
                      brand: brand,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.name],
                      validator: (value) => (value?.trim().length ?? 0) >= 2
                          ? null
                          : 'نام خود را وارد کنید.',
                    ),
                    const SizedBox(height: 13),
                  ],
                  _ExperienceTextField(
                    key: const ValueKey('auth-email'),
                    controller: _email,
                    label: 'ایمیل',
                    icon: Icons.alternate_email_rounded,
                    brand: brand,
                    keyboardType: TextInputType.emailAddress,
                    textDirection: TextDirection.ltr,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.email],
                    validator: (value) => _looksLikeEmail(value?.trim() ?? '')
                        ? null
                        : 'ایمیل معتبر وارد کنید.',
                  ),
                  const SizedBox(height: 13),
                  _ExperienceTextField(
                    key: const ValueKey('auth-password'),
                    controller: _password,
                    label: 'رمز عبور',
                    icon: Icons.lock_outline_rounded,
                    brand: brand,
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
                      onPressed: () => setState(() => _obscure = !_obscure),
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
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
                    const SizedBox(height: 13),
                    _ExperienceTextField(
                      key: const ValueKey('auth-confirm-password'),
                      controller: _confirmPassword,
                      label: 'تکرار رمز عبور',
                      icon: Icons.lock_reset_rounded,
                      brand: brand,
                      obscureText: _obscureConfirm,
                      textDirection: TextDirection.ltr,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.newPassword],
                      suffix: IconButton(
                        tooltip: _obscureConfirm
                            ? 'نمایش تکرار رمز'
                            : 'پنهان‌کردن تکرار رمز',
                        onPressed: () =>
                            setState(() => _obscureConfirm = !_obscureConfirm),
                        icon: Icon(
                          _obscureConfirm
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                      ),
                      validator: (value) => value == _password.text
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
                        onPressed: _busy ? null : _sendPasswordReset,
                        style: TextButton.styleFrom(
                          foregroundColor: brand.primary,
                        ),
                        child: const Text('رمز عبور را فراموش کرده‌ام'),
                      ),
                    ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              _StatusBanner(
                message: _error!,
                icon: Icons.error_outline_rounded,
                color: Theme.of(context).colorScheme.error,
              ),
            ],
            if (_success != null) ...[
              const SizedBox(height: 8),
              _StatusBanner(
                message: _success!,
                icon: Icons.mark_email_read_outlined,
                color: brand.primary,
              ),
            ],
            const SizedBox(height: 18),
            _GradientActionButton(
              key: const ValueKey('auth-submit'),
              brand: brand,
              busy: _busy,
              label: isSignUp ? 'ساخت حساب امن' : 'ورود امن',
              icon: isSignUp
                  ? Icons.person_add_alt_1_rounded
                  : Icons.shield_rounded,
              onPressed: _submit,
            ),
            if (LifeMateFeatureFlags.googleAuthEnabled ||
                LifeMateFeatureFlags.phoneOtpEnabled) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 15),
                child: Row(
                  children: [
                    Expanded(child: Divider()),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: Text(
                        'یا با روشی دیگر',
                        style: TextStyle(
                          color: Color(0xFF8C9AB1),
                          fontSize: 11,
                        ),
                      ),
                    ),
                    Expanded(child: Divider()),
                  ],
                ),
              ),
              if (LifeMateFeatureFlags.phoneOtpEnabled)
                _PhoneOtpButton(brand: brand, enabled: !_busy),
              if (LifeMateFeatureFlags.phoneOtpEnabled &&
                  LifeMateFeatureFlags.googleAuthEnabled)
                const SizedBox(height: 10),
              if (LifeMateFeatureFlags.googleAuthEnabled)
                OutlinedButton.icon(
                  key: const ValueKey('auth-google'),
                  onPressed: _busy ? null : _signInWithGoogle,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    foregroundColor: brand.ink,
                    side: BorderSide(
                      color: brand.primary.withValues(alpha: 0.16),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  icon: const Text(
                    'G',
                    style: TextStyle(
                      color: Color(0xFF4285F4),
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                  label: const Text(
                    'ادامه با حساب گوگل',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
            ],
            const SizedBox(height: 16),
            _PrivacyPromise(brand: brand),
          ],
        ),
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

class _AuthHero extends StatelessWidget {
  const _AuthHero({
    required this.brand,
    required this.logoAssetPath,
    required this.mode,
  });

  final _BrandPalette brand;
  final String logoAssetPath;
  final _AuthMode mode;

  @override
  Widget build(BuildContext context) {
    final signUp = mode == _AuthMode.signUp;
    return Column(
      children: [
        Container(
          width: 108,
          height: 108,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.56),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white.withValues(alpha: 0.86)),
            boxShadow: [
              BoxShadow(
                color: brand.primary.withValues(alpha: 0.14),
                blurRadius: 26,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Hero(
            tag: '${brand.appName}-auth-logo',
            child: Image.asset(
              logoAssetPath,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) =>
                  Icon(brand.heroIcon, size: 68, color: brand.primary),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          brand.eyebrow,
          style: TextStyle(
            color: brand.primary,
            fontSize: 15,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          child: Text(
            signUp ? 'ساخت حساب جدید' : 'خوش آمدید',
            key: ValueKey(signUp),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: brand.ink,
              fontSize: 34,
              height: 1.25,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(height: 9),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          child: Text(
            signUp ? brand.signUpSubtitle : brand.signInSubtitle,
            key: ValueKey('subtitle-$signUp'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF687895),
              fontSize: 14,
              height: 1.75,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Icon(brand.accentIcon, color: brand.primary, size: 24),
      ],
    );
  }
}

class _AuthModeSelector extends StatelessWidget {
  const _AuthModeSelector({
    required this.mode,
    required this.brand,
    required this.enabled,
    required this.onChanged,
  });

  final _AuthMode mode;
  final _BrandPalette brand;
  final bool enabled;
  final ValueChanged<_AuthMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: brand.softSurface,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Expanded(
            child: _AuthModeButton(
              label: 'ورود',
              selected: mode == _AuthMode.signIn,
              brand: brand,
              enabled: enabled,
              onTap: () => onChanged(_AuthMode.signIn),
            ),
          ),
          Expanded(
            child: _AuthModeButton(
              label: 'ثبت‌نام',
              selected: mode == _AuthMode.signUp,
              brand: brand,
              enabled: enabled,
              onTap: () => onChanged(_AuthMode.signUp),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthModeButton extends StatelessWidget {
  const _AuthModeButton({
    required this.label,
    required this.selected,
    required this.brand,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final _BrandPalette brand;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(18),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 230),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(vertical: 13),
            decoration: BoxDecoration(
              color: selected ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(18),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: brand.primary.withValues(alpha: 0.13),
                        blurRadius: 13,
                        offset: const Offset(0, 5),
                      ),
                    ]
                  : null,
            ),
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? brand.primary : const Color(0xFF7B879B),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 230),
                  margin: const EdgeInsets.only(top: 6),
                  width: selected ? 44 : 0,
                  height: 3,
                  decoration: BoxDecoration(
                    color: brand.primary,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ExperienceTextField extends StatelessWidget {
  const _ExperienceTextField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.brand,
    this.keyboardType,
    this.textDirection,
    this.textInputAction,
    this.autofillHints,
    this.obscureText = false,
    this.suffix,
    this.validator,
    this.onSubmitted,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final _BrandPalette brand;
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
      style: TextStyle(color: brand.ink, fontWeight: FontWeight.w700),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF8994A5)),
        prefixIcon: Padding(
          padding: const EdgeInsets.all(8),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: brand.primary.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: brand.primary),
          ),
        ),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 58,
          minHeight: 54,
        ),
        suffixIcon: suffix,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.74),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: brand.primary.withValues(alpha: 0.11)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: brand.primary, width: 1.7),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.error,
            width: 1.7,
          ),
        ),
      ),
    );
  }
}

class _GradientActionButton extends StatelessWidget {
  const _GradientActionButton({
    required this.brand,
    required this.busy,
    required this.label,
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final _BrandPalette brand;
  final bool busy;
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: !busy,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: busy ? 0.82 : 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [brand.primary, brand.primaryDeep],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
            ),
            borderRadius: BorderRadius.circular(19),
            boxShadow: [
              BoxShadow(
                color: brand.primary.withValues(alpha: 0.32),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: busy ? null : onPressed,
              borderRadius: BorderRadius.circular(19),
              child: SizedBox(
                height: 58,
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: busy
                        ? const SizedBox.square(
                            key: ValueKey('busy'),
                            dimension: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: Colors.white,
                            ),
                          )
                        : Row(
                            key: const ValueKey('ready'),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(icon, color: Colors.white, size: 22),
                              const SizedBox(width: 10),
                              Text(
                                label,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
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

class _PrivacyPromise extends StatelessWidget {
  const _PrivacyPromise({required this.brand});

  final _BrandPalette brand;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: brand.softSurface.withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: brand.primary.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(Icons.verified_user_rounded, color: brand.primary),
          ),
          const SizedBox(width: 11),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'امنیت و حریم خصوصی شما برای ما ارزشمند است',
                  style: TextStyle(
                    color: Color(0xFF314064),
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'اطلاعات فقط در محدوده دسترسی مجاز نمایش داده می‌شود.',
                  style: TextStyle(
                    color: Color(0xFF7B879B),
                    fontSize: 10,
                    height: 1.55,
                  ),
                ),
              ],
            ),
          ),
          Icon(brand.accentIcon, color: brand.primary, size: 19),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
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
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: color, fontSize: 12, height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
