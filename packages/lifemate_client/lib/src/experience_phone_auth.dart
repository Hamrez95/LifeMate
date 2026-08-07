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
      label: const Text(
        'ورود با شماره موبایل',
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
        _message = 'کد یک‌بارمصرف برای شماره شما ارسال شد.';
      });
    } on TimeoutException {
      if (mounted) setState(() => _error = 'ارسال کد بیش از حد طول کشید.');
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = _friendlyPhoneError(error));
    } catch (_) {
      if (mounted) setState(() => _error = 'ارسال کد انجام نشد. دوباره تلاش کنید.');
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
      if (mounted) setState(() => _error = 'بررسی کد بیش از حد طول کشید.');
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = _friendlyPhoneError(error));
    } catch (_) {
      if (mounted) setState(() => _error = 'کد تأیید نشد. دوباره تلاش کنید.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final brand = widget.brand;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + bottomInset),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
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
                      child: Icon(Icons.phone_android_rounded, color: brand.primary),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ورود با موبایل',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'شماره را با فرمت بین‌المللی وارد کنید.',
                            style: TextStyle(fontSize: 12, color: Color(0xFF718096)),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'بستن',
                      onPressed: _busy ? null : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                TextField(
                  key: const ValueKey('auth-phone-number'),
                  controller: _phone,
                  enabled: !_busy && !_codeSent,
                  keyboardType: TextInputType.phone,
                  textDirection: TextDirection.ltr,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  decoration: InputDecoration(
                    labelText: 'شماره موبایل',
                    hintText: '+989121234567',
                    prefixIcon: const Icon(Icons.phone_outlined),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
                if (_codeSent) ...[
                  const SizedBox(height: 13),
                  TextField(
                    key: const ValueKey('auth-phone-otp-code'),
                    controller: _otp,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    textDirection: TextDirection.ltr,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    maxLength: 10,
                    decoration: InputDecoration(
                      labelText: 'کد یک‌بارمصرف',
                      counterText: '',
                      prefixIcon: const Icon(Icons.password_rounded),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
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
                    style: TextStyle(color: brand.primary, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ],
                const SizedBox(height: 18),
                FilledButton.icon(
                  key: ValueKey(_codeSent ? 'auth-phone-verify' : 'auth-phone-send'),
                  onPressed: _busy ? null : (_codeSent ? _verifyCode : _sendCode),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    backgroundColor: brand.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
                  ),
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Icon(_codeSent ? Icons.verified_user_outlined : Icons.sms_outlined),
                  label: Text(_codeSent ? 'تأیید و ورود' : 'ارسال کد'),
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
                    child: const Text('اصلاح شماره موبایل'),
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
      return 'تعداد درخواست‌ها زیاد بوده است؛ کمی بعد دوباره تلاش کنید.';
    }
    if (message.contains('expired') || message.contains('invalid')) {
      return 'کد واردشده معتبر نیست یا منقضی شده است.';
    }
    if (message.contains('phone')) {
      return 'شماره موبایل را با فرمت +98 وارد کنید.';
    }
    return 'ورود با شماره موبایل انجام نشد.';
  }
}
