part of 'lifemate_experience_gate.dart';

class _PhoneOtpButton extends StatelessWidget {
  const _PhoneOtpButton({required this.brand, required this.enabled});

  final _BrandPalette brand;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      key: ValueKey('auth-phone-otp'),
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
        minimumSize: Size.fromHeight(52),
        foregroundColor: brand.ink,
        side: BorderSide(color: brand.primary.withValues(alpha: 0.16)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      icon: Icon(Icons.sms_outlined, color: brand.primary),
      label: Text(
        LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'ورود با شماره موبایل',
            en: "Login with mobile number",
          ),
          en: "Login with mobile number",
        ),
        style: TextStyle(fontWeight: FontWeight.w800),
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
  final _phone = TextEditingController(text: '+98');
  final _otp = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  String? _error;
  String? _message;

  @override
  void dispose() {
    _phone.dispose();
    _otp.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      await LifeMateAuth.sendPhoneOtp(phoneE164: _phone.text).timeout(_timeout);
      if (!mounted) return;
      setState(() {
        _codeSent = true;
        _message = LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'کد یک‌بارمصرف برای شماره شما ارسال شد.',
            en: "A one-time code has been sent to your number.",
          ),
          en: "A one-time code has been sent to your number.",
        );
      });
    } on TimeoutException {
      if (mounted)
        setState(
          () => _error = LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'ارسال کد بیش از حد طول کشید.',
              en: "It took too long to send the code.",
            ),
            en: "It took too long to send the code.",
          ),
        );
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = _friendlyPhoneError(error));
    } catch (_) {
      if (mounted)
        setState(
          () => _error = LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'ارسال کد انجام نشد. دوباره تلاش کنید.',
              en: "The code could not be sent. Try again.",
            ),
            en: "The code could not be sent. Try again.",
          ),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyCode() async {
    if (_busy) return;
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
      if (mounted)
        setState(
          () => _error = LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'بررسی کد بیش از حد طول کشید.',
              en: "Code review took too long.",
            ),
            en: "Code review took too long.",
          ),
        );
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = _friendlyPhoneError(error));
    } catch (_) {
      if (mounted)
        setState(
          () => _error = LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'کد تأیید نشد. دوباره تلاش کنید.',
              en: "The code was not verified. Try again.",
            ),
            en: "The code was not verified. Try again.",
          ),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
            padding: EdgeInsets.fromLTRB(20, 18, 20, 24),
            child: Column(
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
                      child: Icon(
                        Icons.phone_android_rounded,
                        color: brand.primary,
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            LifeMateRuntimeLocale.select(
                              fa: LifeMateRuntimeLocale.select(
                                fa: 'ورود با موبایل',
                                en: "Login with mobile",
                              ),
                              en: "Login with mobile",
                            ),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            LifeMateRuntimeLocale.select(
                              fa: LifeMateRuntimeLocale.select(
                                fa: 'شماره را با فرمت بین‌المللی وارد کنید.',
                                en: "Enter the number in international format.",
                              ),
                              en: "Enter the number in international format.",
                            ),
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF718096),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'بستن',
                          en: "to close",
                        ),
                        en: "to close",
                      ),
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                SizedBox(height: 18),
                TextField(
                  key: ValueKey('auth-phone-number'),
                  controller: _phone,
                  enabled: !_busy && !_codeSent,
                  keyboardType: TextInputType.phone,
                  inputFormatters: const [LifeMateLocaleDigitInputFormatter()],
                  textDirection: TextDirection.ltr,
                  autofillHints: [AutofillHints.telephoneNumber],
                  decoration: InputDecoration(
                    labelText: LifeMateRuntimeLocale.select(
                      fa: LifeMateRuntimeLocale.select(
                        fa: 'شماره موبایل',
                        en: "mobile number",
                      ),
                      en: "mobile number",
                    ),
                    hintText: '+989121234567',
                    prefixIcon: Icon(Icons.phone_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
                if (_codeSent) ...[
                  SizedBox(height: 13),
                  TextField(
                    key: ValueKey('auth-phone-otp-code'),
                    controller: _otp,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    inputFormatters: const [
                      LifeMateLocaleDigitInputFormatter(),
                    ],
                    textDirection: TextDirection.ltr,
                    autofillHints: [AutofillHints.oneTimeCode],
                    maxLength: 10,
                    decoration: InputDecoration(
                      labelText: LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'کد یک‌بارمصرف',
                          en: "One-time use code",
                        ),
                        en: "One-time use code",
                      ),
                      counterText: '',
                      prefixIcon: Icon(Icons.password_rounded),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onSubmitted: (_) => _verifyCode(),
                  ),
                ],
                if (_error != null) ...[
                  SizedBox(height: 12),
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
                  SizedBox(height: 12),
                  Text(
                    _message!,
                    style: TextStyle(
                      color: brand.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                SizedBox(height: 18),
                FilledButton.icon(
                  key: ValueKey(
                    _codeSent ? 'auth-phone-verify' : 'auth-phone-send',
                  ),
                  onPressed: _busy
                      ? null
                      : (_codeSent ? _verifyCode : _sendCode),
                  style: FilledButton.styleFrom(
                    minimumSize: Size.fromHeight(52),
                    backgroundColor: brand.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(17),
                    ),
                  ),
                  icon: _busy
                      ? SizedBox(
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
                            fa: LifeMateRuntimeLocale.select(
                              fa: 'تأیید و ورود',
                              en: "Verification and login",
                            ),
                            en: "Verification and login",
                          )
                        : LifeMateRuntimeLocale.select(
                            fa: LifeMateRuntimeLocale.select(
                              fa: 'ارسال کد',
                              en: "Send code",
                            ),
                            en: "Send code",
                          ),
                  ),
                ),
                if (_codeSent) ...[
                  SizedBox(height: 6),
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
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'اصلاح شماره موبایل',
                          en: "Modify mobile number",
                        ),
                        en: "Modify mobile number",
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _friendlyPhoneError(AuthException error) {
    final message = error.message.toLowerCase();
    if (message.contains('rate') || message.contains('limit')) {
      return LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'تعداد درخواست‌ها زیاد بوده است؛ کمی بعد دوباره تلاش کنید.',
          en: "The number of requests has been high; Try again later.",
        ),
        en: "The number of requests has been high; Try again later.",
      );
    }
    if (message.contains('expired') || message.contains('invalid')) {
      return LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'کد واردشده معتبر نیست یا منقضی شده است.',
          en: "The code entered is invalid or has expired.",
        ),
        en: "The code entered is invalid or has expired.",
      );
    }
    if (message.contains('phone')) {
      return LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'شماره موبایل را با فرمت +98 وارد کنید.',
          en: "Enter the mobile number in +98 format.",
        ),
        en: "Enter the mobile number in +98 format.",
      );
    }
    return LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'ورود با شماره موبایل انجام نشد.',
        en: "Login with mobile number was not done.",
      ),
      en: "Login with mobile number was not done.",
    );
  }
}
