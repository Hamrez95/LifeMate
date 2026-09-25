import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lifemate_client/lifemate_client.dart';

class LifeMateShellAuth extends StatefulWidget {
  const LifeMateShellAuth({
    required this.isPersian,
    this.logoAssetPath = 'assets/branding/lifemate_logo.png',
    super.key,
  });

  final bool isPersian;
  final String logoAssetPath;

  @override
  State<LifeMateShellAuth> createState() => _LifeMateShellAuthState();
}

class _LifeMateShellAuthState extends State<LifeMateShellAuth> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _phone = TextEditingController();
  final _code = TextEditingController();
  bool _signUp = false;
  bool _phoneMode = LifeMateFeatureFlags.phoneOtpEnabled;
  bool _codeSent = false;
  bool _busy = false;
  String? _notice;

  String t(String en, String fa) => widget.isPersian ? fa : en;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _submitEmail() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      if (_signUp) {
        await LifeMateAuth.signUpWithEmail(
          email: _email.text,
          password: _password.text,
          appName: 'LifeMate',
        );
        setState(
          () => _notice = t(
            'Check your email to confirm your account.',
            'برای تأیید حساب، ایمیلت را بررسی کن.',
          ),
        );
      } else {
        await LifeMateAuth.signInWithEmail(
          email: _email.text,
          password: _password.text,
        );
      }
    } on AuthException catch (error) {
      setState(() => _notice = _friendlyAuthError(error));
    } catch (_) {
      setState(
        () => _notice = t(
          'Sign in could not be completed. Check your connection and try again.',
          'ورود کامل نشد. اتصال اینترنت را بررسی و دوباره تلاش کن.',
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitPhone() async {
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final phone = LifeMateIranPhone.normalizeE164(_phone.text);
      if (!_codeSent) {
        await LifeMateAuth.sendPhoneOtp(
          phoneE164: phone,
          intent: _signUp
              ? LifeMatePhoneOtpIntent.signUp
              : LifeMatePhoneOtpIntent.signIn,
        );
        setState(() {
          _codeSent = true;
          _notice = t('Code sent.', 'کد ارسال شد.');
        });
      } else {
        await LifeMateAuth.verifyPhoneOtp(phoneE164: phone, token: _code.text);
      }
    } on FormatException {
      setState(
        () => _notice = t(
          'Enter a valid mobile number.',
          'شماره موبایل معتبر وارد کن.',
        ),
      );
    } on AuthException catch (error) {
      setState(() => _notice = _friendlyAuthError(error));
    } catch (_) {
      setState(
        () => _notice = t(
          'SMS sign in is unavailable right now.',
          'ورود پیامکی در حال حاضر در دسترس نیست.',
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendlyAuthError(AuthException error) {
    final text = '${error.message} ${error.code ?? ''}'.toLowerCase();
    if (text.contains('invalid login credentials')) {
      return t(
        'Email or password is incorrect.',
        'ایمیل یا گذرواژه درست نیست.',
      );
    }
    if (text.contains('already registered')) {
      return t(
        'This email already has an account. Sign in instead.',
        'این ایمیل قبلاً حساب دارد؛ وارد شو.',
      );
    }
    return t(
      'Authentication could not be completed. Try again shortly.',
      'احراز هویت کامل نشد؛ کمی بعد دوباره تلاش کن.',
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          'assets/branding/lifemate_launch_city.jpg',
          fit: BoxFit.cover,
        ),
        const ColoredBox(color: Color(0x99101D38)),
        SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(22),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 104,
                      child: Image.asset(
                        widget.logoAssetPath,
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      t('Your life, together.', 'زندگی، با هم.'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: const Color(0xF6FFFDF8),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: const Color(0x66FFFFFF)),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x55000000),
                            blurRadius: 28,
                            offset: Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              _signUp
                                  ? t('Create your account', 'ساخت حساب')
                                  : t('Welcome back', 'خوش برگشتی'),
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              t(
                                'One account for your LifeMate products.',
                                'یک حساب برای همه محصولات LifeMate.',
                              ),
                              style: const TextStyle(color: Color(0xFF5E6968)),
                            ),
                            const SizedBox(height: 18),
                            if (_phoneMode) ...[
                              TextFormField(
                                controller: _phone,
                                keyboardType: TextInputType.phone,
                                inputFormatters: [
                                  LengthLimitingTextInputFormatter(16),
                                ],
                                decoration: _decoration(
                                  t('Mobile number', 'شماره موبایل'),
                                  Icons.phone_iphone_rounded,
                                  hint: '09xxxxxxxxx',
                                ),
                                validator: (value) =>
                                    value == null || value.trim().isEmpty
                                    ? t(
                                        'Enter your mobile number.',
                                        'شماره موبایل را وارد کن.',
                                      )
                                    : null,
                              ),
                              if (_codeSent) ...[
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _code,
                                  keyboardType: TextInputType.number,
                                  decoration: _decoration(
                                    t('Verification code', 'کد تأیید'),
                                    Icons.verified_user_outlined,
                                  ),
                                  validator: (value) =>
                                      value == null || value.trim().length < 6
                                      ? t(
                                          'Enter the code you received.',
                                          'کد دریافت‌شده را وارد کن.',
                                        )
                                      : null,
                                ),
                              ],
                            ] else ...[
                              TextFormField(
                                controller: _email,
                                keyboardType: TextInputType.emailAddress,
                                autofillHints: const [AutofillHints.email],
                                decoration: _decoration(
                                  t('Email', 'ایمیل'),
                                  Icons.alternate_email_rounded,
                                ),
                                validator: (value) =>
                                    value == null || !value.contains('@')
                                    ? t(
                                        'Enter a valid email.',
                                        'ایمیل معتبر وارد کن.',
                                      )
                                    : null,
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _password,
                                obscureText: true,
                                autofillHints: [
                                  _signUp
                                      ? AutofillHints.newPassword
                                      : AutofillHints.password,
                                ],
                                decoration: _decoration(
                                  t('Password', 'گذرواژه'),
                                  Icons.lock_outline_rounded,
                                ),
                                validator: (value) =>
                                    value == null || value.length < 8
                                    ? t(
                                        'Use at least 8 characters.',
                                        'حداقل ۸ نویسه وارد کن.',
                                      )
                                    : null,
                              ),
                            ],
                            if (_notice != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                _notice!,
                                style: const TextStyle(
                                  color: Color(0xFF385A50),
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                            const SizedBox(height: 18),
                            FilledButton.icon(
                              onPressed: _busy
                                  ? null
                                  : (_phoneMode &&
                                            !LifeMateFeatureFlags
                                                .phoneOtpEnabled
                                        ? null
                                        : _phoneMode
                                        ? _submitPhone
                                        : _submitEmail),
                              icon: _busy
                                  ? const SizedBox(
                                      width: 17,
                                      height: 17,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.arrow_forward_rounded),
                              label: Text(
                                _phoneMode
                                    ? (_codeSent
                                          ? t(
                                              'Verify and continue',
                                              'تأیید و ادامه',
                                            )
                                          : t(
                                              'Send verification code',
                                              'ارسال کد تأیید',
                                            ))
                                    : (_signUp
                                          ? t('Create account', 'ساخت حساب')
                                          : t('Sign in', 'ورود')),
                              ),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(50),
                                backgroundColor: const Color(0xFF287B67),
                              ),
                            ),
                            if (_phoneMode &&
                                !LifeMateFeatureFlags.phoneOtpEnabled) ...[
                              const SizedBox(height: 8),
                              Text(
                                t(
                                  'SMS sign in is not enabled for this release. Use email for now.',
                                  'ورود پیامکی در این نسخه فعال نیست؛ فعلاً از ایمیل استفاده کن.',
                                ),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF687472),
                                ),
                              ),
                            ],
                            const SizedBox(height: 7),
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => setState(() {
                                      _phoneMode = !_phoneMode;
                                      _codeSent = false;
                                      _notice = null;
                                    }),
                              child: Text(
                                _phoneMode
                                    ? t('Use email instead', 'استفاده از ایمیل')
                                    : t(
                                        'Use mobile number',
                                        'استفاده از شماره موبایل',
                                      ),
                              ),
                            ),
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => setState(() {
                                      _signUp = !_signUp;
                                      _codeSent = false;
                                      _notice = null;
                                    }),
                              child: Text(
                                _signUp
                                    ? t(
                                        'Already have an account? Sign in',
                                        'حساب داری؟ وارد شو',
                                      )
                                    : t(
                                        'New to LifeMate? Create an account',
                                        'تازه واردی؟ حساب بساز',
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
      ],
    ),
  );

  InputDecoration _decoration(String label, IconData icon, {String? hint}) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: const Color(0xFFF5F4EE),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide.none,
        ),
      );
}
