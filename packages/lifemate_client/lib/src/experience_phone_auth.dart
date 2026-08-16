part of 'lifemate_experience_gate.dart';

class _PhoneOtpButton extends StatelessWidget {
  const _PhoneOtpButton({
    required this.brand,
    required this.enabled,
  });

  final _BrandPalette brand;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      key: const ValueKey('auth-phone-otp'),
      onPressed: enabled
          ? () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              backgroundColor: Colors.transparent,
              builder: (_) => _PhoneOtpSheet(brand: brand),
            )
          : null,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        foregroundColor: brand.ink,
        side: BorderSide(color: brand.primary.withValues(alpha: 0.16)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      icon: Icon(Icons.sms_outlined, color: brand.primary),
      label: Text(
        LifeMateRuntimeLocale.select(
          fa: 'ادامه با شماره موبایل',
          en: 'Continue with mobile number',
        ),
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _PhoneOtpSheet extends StatefulWidget {
  const _PhoneOtpSheet({required this.brand});

  final _BrandPalette brand;

  @override
  State<_PhoneOtpSheet> createState() => _PhoneOtpSheetState();
}

class _PhoneOtpSheetState extends State<_PhoneOtpSheet> {
  static const _timeout = Duration(seconds: 20);
  final _phone = TextEditingController(text: '09');
  final _otp = TextEditingController();
  LifeMatePhoneOtpIntent? _intent;
  bool _codeSent = false;
  bool _busy = false;
  String? _error;
  String? _message;

  bool get _isSignUp => _intent == LifeMatePhoneOtpIntent.signUp;

  @override
  void dispose() {
    _phone.dispose();
    _otp.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final intent = _intent;
    if (_busy || intent == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      await LifeMateAuth.sendPhoneOtp(
        phoneE164: _phone.text,
        intent: intent,
      ).timeout(_timeout);
      if (!mounted) return;
      setState(() {
        _codeSent = true;
        _message = LifeMateRuntimeLocale.select(
          fa: 'اگر ادامه این درخواست مجاز باشد، کد یک‌بارمصرف برای شماره واردشده ارسال می‌شود.',
          en: 'If this request can proceed, a one-time code will be sent to the entered number.',
        );
      });
    } on TimeoutException {
      if (mounted) {
        setState(
          () => _error = LifeMateRuntimeLocale.select(
            fa: 'ارسال کد بیش از حد طول کشید. کمی بعد دوباره تلاش کنید.',
            en: 'Sending the code took too long. Try again later.',
          ),
        );
      }
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = _friendlyPhoneError(error));
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = LifeMateRuntimeLocale.select(
            fa: 'درخواست کد انجام نشد. کمی بعد دوباره تلاش کنید.',
            en: 'The code request could not be completed. Try again later.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyCode() async {
    if (_busy || _intent == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      await LifeMateAuth.verifyPhoneOtp(
        phoneE164: _phone.text,
        token: _otp.text,
      ).timeout(_timeout);
      if (!mounted) return;
      Navigator.of(context).pop();
    } on TimeoutException {
      if (mounted) {
        setState(
          () => _error = LifeMateRuntimeLocale.select(
            fa: 'بررسی کد بیش از حد طول کشید. کمی بعد دوباره تلاش کنید.',
            en: 'Code verification took too long. Try again later.',
          ),
        );
      }
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = _friendlyPhoneError(error));
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = LifeMateRuntimeLocale.select(
            fa: 'کد تأیید نشد. دوباره تلاش کنید.',
            en: 'The code was not verified. Try again.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _selectIntent(LifeMatePhoneOtpIntent intent) {
    if (_busy) return;
    setState(() {
      _intent = intent;
      _codeSent = false;
      _otp.clear();
      _error = null;
      _message = null;
    });
  }

  void _changeIntent() {
    if (_busy) return;
    setState(() {
      _intent = null;
      _codeSent = false;
      _phone.text = '09';
      _otp.clear();
      _error = null;
      _message = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final brand = widget.brand;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Directionality(
      textDirection: LifeMateRuntimeLocale.isPersian
          ? TextDirection.rtl
          : TextDirection.ltr,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + bottomInset),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
            child: _intent == null
                ? _buildIntentChooser(brand)
                : _buildOtpForm(brand),
          ),
        ),
      ),
    );
  }

  Widget _buildIntentChooser(_BrandPalette brand) {
    return Column(
      key: const ValueKey('auth-phone-intent-chooser'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: brand.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(Icons.phone_android_rounded, color: brand.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                LifeMateRuntimeLocale.select(
                  fa: 'با شماره موبایل چه کاری می‌خواهید انجام دهید؟',
                  en: 'How do you want to continue with your mobile number?',
                ),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            IconButton(
              tooltip: LifeMateRuntimeLocale.select(fa: 'بستن', en: 'Close'),
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          key: const ValueKey('auth-phone-intent-signin'),
          onPressed: () => _selectIntent(LifeMatePhoneOtpIntent.signIn),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
            backgroundColor: brand.primary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(17),
            ),
          ),
          icon: const Icon(Icons.login_rounded),
          label: Text(
            LifeMateRuntimeLocale.select(
              fa: 'از قبل حساب LifeMate دارم',
              en: 'I already have a LifeMate account',
            ),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          key: const ValueKey('auth-phone-intent-signup'),
          onPressed: () => _selectIntent(LifeMatePhoneOtpIntent.signUp),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
            foregroundColor: brand.ink,
            side: BorderSide(color: brand.primary.withValues(alpha: .22)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(17),
            ),
          ),
          icon: const Icon(Icons.person_add_alt_1_rounded),
          label: Text(
            LifeMateRuntimeLocale.select(
              fa: 'حساب جدید با موبایل بسازم',
              en: 'Create a new account with mobile',
            ),
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: brand.primary.withValues(alpha: .07),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            LifeMateRuntimeLocale.select(
              fa: 'اگر قبلاً با ایمیل یا روش دیگری حساب LifeMate ساخته‌اید، ابتدا وارد همان حساب شوید و شماره موبایل را از «امنیت حساب» اضافه کنید. ثبت‌نام جدید، حساب‌های قبلی را خودکار ادغام نمی‌کند.',
              en: 'If you already created a LifeMate account with email or another method, sign in to that account first and add your mobile number from Account security. New signup never auto-merges an existing account.',
            ),
            style: const TextStyle(
              color: Color(0xFF5F6B7D),
              fontSize: 12,
              height: 1.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOtpForm(_BrandPalette brand) {
    return Column(
      key: ValueKey('auth-phone-form-${_isSignUp ? 'signup' : 'signin'}'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: brand.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(Icons.phone_android_rounded, color: brand.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    LifeMateRuntimeLocale.select(
                      fa: _isSignUp
                          ? 'ثبت‌نام امن با موبایل'
                          : 'ورود امن با موبایل',
                      en: _isSignUp
                          ? 'Secure mobile sign up'
                          : 'Secure mobile login',
                    ),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    LifeMateRuntimeLocale.select(
                      fa: 'شماره موبایل ایران را وارد کنید؛ فرمت‌های 09 و +98 پذیرفته می‌شوند.',
                      en: 'Enter an Iranian mobile number; 09 and +98 formats are accepted.',
                    ),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF718096),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: LifeMateRuntimeLocale.select(fa: 'بستن', en: 'Close'),
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          key: const ValueKey('auth-phone-change-intent'),
          onPressed: _busy ? null : _changeIntent,
          icon: const Icon(Icons.swap_horiz_rounded, size: 18),
          label: Text(
            LifeMateRuntimeLocale.select(
              fa: 'تغییر انتخاب ورود / ثبت‌نام',
              en: 'Change login / signup choice',
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('auth-phone-number'),
          controller: _phone,
          enabled: !_busy && !_codeSent,
          keyboardType: TextInputType.phone,
          inputFormatters: const [LifeMateLocaleDigitInputFormatter()],
          textDirection: TextDirection.ltr,
          autofillHints: const [AutofillHints.telephoneNumber],
          decoration: InputDecoration(
            labelText: LifeMateRuntimeLocale.select(
              fa: 'شماره موبایل',
              en: 'Mobile number',
            ),
            hintText: '09121234567',
            prefixIcon: const Icon(Icons.phone_outlined),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        if (_codeSent) ...[
          const SizedBox(height: 13),
          TextField(
            key: const ValueKey('auth-phone-otp-code'),
            controller: _otp,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            inputFormatters: const [LifeMateLocaleDigitInputFormatter()],
            textDirection: TextDirection.ltr,
            autofillHints: const [AutofillHints.oneTimeCode],
            maxLength: 10,
            decoration: InputDecoration(
              labelText: LifeMateRuntimeLocale.select(
                fa: 'کد یک‌بارمصرف',
                en: 'One-time code',
              ),
              counterText: '',
              prefixIcon: const Icon(Icons.password_rounded),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            onSubmitted: (_) => _verifyCode(),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        if (_message != null) ...[
          const SizedBox(height: 12),
          Text(
            _message!,
            style: TextStyle(
              color: brand.primary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        const SizedBox(height: 18),
        FilledButton.icon(
          key: ValueKey(_codeSent ? 'auth-phone-verify' : 'auth-phone-send'),
          onPressed: _busy ? null : (_codeSent ? _verifyCode : _sendCode),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            backgroundColor: brand.primary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(17),
            ),
          ),
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Icon(
                  _codeSent
                      ? Icons.verified_user_outlined
                      : Icons.sms_outlined,
                ),
          label: Text(
            _codeSent
                ? LifeMateRuntimeLocale.select(
                    fa: _isSignUp ? 'تأیید و ثبت‌نام' : 'تأیید و ورود',
                    en: _isSignUp
                        ? 'Verify and sign up'
                        : 'Verify and login',
                  )
                : LifeMateRuntimeLocale.select(
                    fa: 'ارسال کد',
                    en: 'Send code',
                  ),
          ),
        ),
        if (_codeSent) ...[
          const SizedBox(height: 6),
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                    _codeSent = false;
                    _otp.clear();
                    _error = null;
                    _message = null;
                  }),
            child: Text(
              LifeMateRuntimeLocale.select(
                fa: 'اصلاح شماره موبایل',
                en: 'Modify mobile number',
              ),
            ),
          ),
        ],
      ],
    );
  }

  static String _friendlyPhoneError(AuthException error) {
    final message = error.message.toLowerCase();
    if (message.contains('rate') || message.contains('limit')) {
      return LifeMateRuntimeLocale.select(
        fa: 'تعداد درخواست‌ها زیاد بوده است؛ کمی بعد دوباره تلاش کنید.',
        en: 'Too many requests were made. Try again later.',
      );
    }
    if (message.contains('phone') ||
        message.contains('mobile') ||
        message.contains('iranian')) {
      return LifeMateRuntimeLocale.select(
        fa: 'شماره موبایل ایران معتبر وارد کنید.',
        en: 'Enter a valid Iranian mobile number.',
      );
    }
    if (message.contains('expired') || message.contains('invalid')) {
      return LifeMateRuntimeLocale.select(
        fa: 'کد واردشده معتبر نیست یا منقضی شده است.',
        en: 'The entered code is invalid or has expired.',
      );
    }
    return LifeMateRuntimeLocale.select(
      fa: 'احراز هویت با شماره موبایل انجام نشد. کمی بعد دوباره تلاش کنید.',
      en: 'Mobile authentication could not be completed. Try again later.',
    );
  }
}
