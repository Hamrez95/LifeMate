import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:smart_auth/smart_auth.dart';

import 'onboarding_components.dart';
import 'onboarding_specialized.dart';
import 'onboarding_theme.dart';

enum _AuthChannel { email, phone }
enum _EmailMode { signIn, signUp }
enum _PhoneStage { intent, phone, otp }

/// V3 authentication presentation shared by WellMate and CareMate.
///
/// Auth/session truth remains in `lifemate_client`; this widget only owns
/// transient form state. It intentionally does not collect display name or
/// product intent, which belong to the post-auth onboarding flow.
class LifeMateSharedAuthExperience extends StatefulWidget {
  const LifeMateSharedAuthExperience({
    super.key,
    required this.appName,
    required this.logoAssetPath,
  });

  final String appName;
  final String logoAssetPath;

  @override
  State<LifeMateSharedAuthExperience> createState() =>
      _LifeMateSharedAuthExperienceState();
}

class _LifeMateSharedAuthExperienceState
    extends State<LifeMateSharedAuthExperience> {
  static const _timeout = Duration(seconds: 20);
  static const _resendDelaySeconds = 60;

  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _phone = TextEditingController(text: '09');
  final _otp = TextEditingController();
  final SmartAuth _smartAuth = SmartAuth.instance;

  late _AuthChannel _channel;
  _EmailMode _emailMode = _EmailMode.signIn;
  _PhoneStage _phoneStage = _PhoneStage.intent;
  LifeMatePhoneOtpIntent? _phoneIntent;
  bool _busy = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _error;
  String? _message;
  int _resendSeconds = 0;
  Timer? _resendTimer;

  bool get _isPersian => LifeMateRuntimeLocale.isPersian;
  bool get _phoneEnabled => LifeMateFeatureFlags.phoneOtpEnabled;
  bool get _googleEnabled => LifeMateFeatureFlags.googleAuthEnabled;
  bool get _supportsAndroidSmsConsent =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  LifeMateOnboardingTheme get _theme => LifeMateOnboardingTheme.shared;

  @override
  void initState() {
    super.initState();
    _channel = _phoneEnabled && _isPersian
        ? _AuthChannel.phone
        : _AuthChannel.email;
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    if (_supportsAndroidSmsConsent) {
      unawaited(_smartAuth.removeUserConsentApiListener());
    }
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    _phone.dispose();
    _otp.dispose();
    super.dispose();
  }

  void _clearFeedback() {
    _error = null;
    _message = null;
  }

  void _selectChannel(_AuthChannel channel) {
    if (_busy || channel == _AuthChannel.phone && !_phoneEnabled) return;
    if (channel != _AuthChannel.phone) _stopSmsOtpListener();
    setState(() {
      _channel = channel;
      _clearFeedback();
    });
  }

  void _setEmailMode(_EmailMode mode) {
    if (_busy) return;
    setState(() {
      _emailMode = mode;
      _password.clear();
      _confirmPassword.clear();
      _clearFeedback();
    });
  }

  bool _looksLikeEmail(String value) {
    final normalized = value.trim();
    return normalized.length <= 254 &&
        RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(normalized);
  }

  String _networkError() => LifeMateRuntimeLocale.select(
        fa: 'ارتباط با سرویس ورود برقرار نشد. دوباره تلاش کنید.',
        en: 'The sign-in service could not be reached. Try again.',
      );

  String _timeoutError() => LifeMateRuntimeLocale.select(
        fa: 'پاسخی دریافت نشد. اتصال را بررسی و دوباره تلاش کنید.',
        en: 'No response was received. Check your connection and try again.',
      );

  String _safeAuthError(AuthException error) {
    final message = error.message.toLowerCase();
    if (message.contains('rate') ||
        message.contains('too many') ||
        message.contains('limit')) {
      return LifeMateRuntimeLocale.select(
        fa: 'تعداد درخواست‌ها زیاد بوده است؛ کمی بعد دوباره تلاش کنید.',
        en: 'Too many requests were made. Try again later.',
      );
    }
    if (message.contains('invalid login') ||
        message.contains('invalid credentials') ||
        message.contains('email not confirmed')) {
      return LifeMateRuntimeLocale.select(
        fa: 'اطلاعات ورود تأیید نشد. ایمیل و رمز عبور را بررسی کنید.',
        en: 'The sign-in details could not be verified. Check your email and password.',
      );
    }
    return LifeMateRuntimeLocale.select(
      fa: 'این درخواست ورود انجام نشد. دوباره تلاش کنید.',
      en: 'This sign-in request could not be completed. Try again.',
    );
  }

  Future<void> _submitEmail() async {
    FocusScope.of(context).unfocus();
    if (_busy) return;
    final email = _email.text.trim();
    if (!_looksLikeEmail(email)) {
      setState(() => _error = LifeMateRuntimeLocale.select(
            fa: 'یک آدرس ایمیل معتبر وارد کنید.',
            en: 'Enter a valid email address.',
          ));
      return;
    }
    if (_password.text.isEmpty) {
      setState(() => _error = LifeMateRuntimeLocale.select(
            fa: 'رمز عبور را وارد کنید.',
            en: 'Enter your password.',
          ));
      return;
    }
    if (_emailMode == _EmailMode.signUp) {
      final policyError = LifeMatePasswordPolicy.validationMessage(
        _password.text,
        isPersian: _isPersian,
      );
      if (policyError != null) {
        setState(() => _error = policyError);
        return;
      }
      if (_password.text != _confirmPassword.text) {
        setState(() => _error = LifeMateRuntimeLocale.select(
              fa: 'تکرار رمز عبور با رمز انتخاب‌شده یکسان نیست.',
              en: 'The password confirmation does not match.',
            ));
        return;
      }
    }

    setState(() {
      _busy = true;
      _clearFeedback();
    });
    try {
      if (_emailMode == _EmailMode.signIn) {
        await LifeMateAuth.signInWithEmail(
          email: email,
          password: _password.text,
        ).timeout(_timeout);
      } else {
        final response = await LifeMateAuth.signUpWithEmail(
          email: email,
          password: _password.text,
          appName: widget.appName,
        ).timeout(_timeout);
        if (!mounted) return;
        if (response.session == null) {
          setState(() {
            _emailMode = _EmailMode.signIn;
            _password.clear();
            _confirmPassword.clear();
            _message = LifeMateRuntimeLocale.select(
              fa: 'اگر ثبت‌نام قابل تکمیل باشد، پیام تأیید برای ایمیل واردشده ارسال می‌شود. پس از تأیید، وارد حساب شوید.',
              en: 'If registration can proceed, a confirmation message will be sent to the entered email. Sign in after confirming it.',
            );
          });
        }
      }
    } on TimeoutException {
      if (mounted) setState(() => _error = _timeoutError());
    } on AuthException catch (error) {
      if (!mounted) return;
      if (_emailMode == _EmailMode.signUp) {
        setState(() {
          _emailMode = _EmailMode.signIn;
          _password.clear();
          _confirmPassword.clear();
          _message = LifeMateRuntimeLocale.select(
            fa: 'اگر این ایمیل امکان ثبت‌نام داشته باشد، مراحل تأیید برای آن ارسال می‌شود. اگر قبلاً حساب دارید، وارد شوید.',
            en: 'If this email can be registered, confirmation steps will be sent. If you already have an account, sign in.',
          );
        });
      } else {
        setState(() => _error = _safeAuthError(error));
      }
    } catch (_) {
      if (mounted) setState(() => _error = _networkError());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _email.text.trim();
    if (!_looksLikeEmail(email) || _busy) {
      setState(() => _error = LifeMateRuntimeLocale.select(
            fa: 'ابتدا ایمیل معتبر خود را وارد کنید.',
            en: 'Enter your valid email first.',
          ));
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _clearFeedback();
    });
    try {
      await LifeMateAuth.requestPasswordReset(
        email: email,
        appName: widget.appName,
      ).timeout(_timeout);
      if (!mounted) return;
      setState(() => _message = LifeMateRuntimeLocale.select(
            fa: 'اگر حسابی با این ایمیل وجود داشته باشد، لینک بازیابی ارسال می‌شود.',
            en: 'If an account exists for this email, a recovery link will be sent.',
          ));
    } on TimeoutException {
      if (mounted) setState(() => _error = _timeoutError());
    } on AuthException catch (error) {
      if (mounted) {
        setState(() => _error = safeRecoveryAuthMessage(
              error.message,
              isPersian: _isPersian,
            ));
      }
    } catch (_) {
      if (mounted) setState(() => _error = _networkError());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _selectPhoneIntent(LifeMatePhoneOtpIntent intent) {
    if (_busy || !_phoneEnabled) return;
    setState(() {
      _phoneIntent = intent;
      _phoneStage = _PhoneStage.phone;
      _otp.clear();
      _clearFeedback();
    });
  }

  void _backPhoneStage() {
    if (_busy) return;
    if (_phoneStage == _PhoneStage.otp) _stopSmsOtpListener();
    setState(() {
      _clearFeedback();
      if (_phoneStage == _PhoneStage.otp) {
        _phoneStage = _PhoneStage.phone;
        _otp.clear();
      } else if (_phoneStage == _PhoneStage.phone) {
        _phoneStage = _PhoneStage.intent;
        _phoneIntent = null;
      }
    });
  }

  void _stopSmsOtpListener() {
    if (!_supportsAndroidSmsConsent) return;
    unawaited(_smartAuth.removeUserConsentApiListener());
  }

  void _startSmsOtpListener() {
    if (!_supportsAndroidSmsConsent) return;
    unawaited(_listenForIncomingSmsOtp());
  }

  Future<void> _listenForIncomingSmsOtp() async {
    try {
      await _smartAuth.removeUserConsentApiListener();
      if (!mounted) return;
      final result = await _smartAuth.getSmsWithUserConsentApi();
      if (!mounted || !result.hasData) return;
      final code = result.requireData.code;
      if (code == null) return;
      final digits = code.replaceAll(RegExp(r'\D'), '');
      if (digits.length != 6 || _channel != _AuthChannel.phone) return;
      _otp.value = TextEditingValue(
        text: digits,
        selection: TextSelection.collapsed(offset: digits.length),
      );
    } catch (_) {
      // SMS consent is a convenience only. Manual OTP entry remains available
      // and we deliberately never log SMS content or OTP values.
    }
  }

  Future<void> _sendPhoneCode() async {
    final intent = _phoneIntent;
    if (_busy || intent == null || !_phoneEnabled) return;
    FocusScope.of(context).unfocus();
    _startSmsOtpListener();
    var sent = false;
    setState(() {
      _busy = true;
      _clearFeedback();
    });
    try {
      await LifeMateAuth.sendPhoneOtp(
        phoneE164: _phone.text,
        intent: intent,
      ).timeout(_timeout);
      sent = true;
      if (!mounted) return;
      _startResendCountdown();
      setState(() {
        _phoneStage = _PhoneStage.otp;
        _message = LifeMateRuntimeLocale.select(
          fa: 'اگر این شماره قابل استفاده باشد، کد ارسال شده است.',
          en: 'If this number can be used, a verification code has been sent.',
        );
      });
    } on TimeoutException {
      if (mounted) setState(() => _error = _timeoutError());
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = _safePhoneError(error));
    } catch (_) {
      if (mounted) setState(() => _error = _networkError());
    } finally {
      if (!sent) _stopSmsOtpListener();
      if (mounted) {
        setState(() => _busy = false);
        if (sent && _phoneStage == _PhoneStage.otp && _otp.text.length == 6) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) unawaited(_verifyPhoneCode());
          });
        }
      }
    }
  }

  String _safePhoneError(AuthException error) {
    final message = error.message.toLowerCase();
    if (message.contains('rate') ||
        message.contains('too many') ||
        message.contains('limit')) {
      return LifeMateRuntimeLocale.select(
        fa: 'تعداد درخواست‌ها زیاد بوده است؛ کمی بعد دوباره تلاش کنید.',
        en: 'Too many requests were made. Try again later.',
      );
    }
    if (message.contains('invalid') && message.contains('phone')) {
      return LifeMateRuntimeLocale.select(
        fa: 'شماره موبایل معتبر ایرانی وارد کنید.',
        en: 'Enter a valid Iranian mobile number.',
      );
    }
    return LifeMateRuntimeLocale.select(
      fa: 'درخواست کد انجام نشد. دوباره تلاش کنید.',
      en: 'The code request could not be completed. Try again.',
    );
  }

  Future<void> _verifyPhoneCode() async {
    if (_busy || _phoneIntent == null || !_phoneEnabled) return;
    setState(() {
      _busy = true;
      _clearFeedback();
    });
    try {
      await LifeMateAuth.verifyPhoneOtp(
        phoneE164: _phone.text,
        token: _otp.text,
      ).timeout(_timeout);
      _stopSmsOtpListener();
    } on TimeoutException {
      if (mounted) setState(() => _error = _timeoutError());
    } on AuthException {
      if (mounted) {
        setState(() => _error = LifeMateRuntimeLocale.select(
              fa: 'کد تأیید نشد. کد را بررسی یا دوباره دریافت کنید.',
              en: 'The code could not be verified. Check it or request a new code.',
            ));
      }
    } catch (_) {
      if (mounted) setState(() => _error = _networkError());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startResendCountdown() {
    _resendTimer?.cancel();
    _resendSeconds = _resendDelaySeconds;
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendSeconds <= 1) {
        timer.cancel();
        setState(() => _resendSeconds = 0);
      } else {
        setState(() => _resendSeconds -= 1);
      }
    });
  }

  Future<void> _signInWithGoogle() async {
    if (_busy || !_googleEnabled) return;
    setState(() {
      _busy = true;
      _clearFeedback();
    });
    try {
      final launched = await LifeMateAuth.signInWithGoogle(
        appName: widget.appName,
      ).timeout(_timeout);
      if (!launched && mounted) {
        setState(() => _error = LifeMateRuntimeLocale.select(
              fa: 'صفحه ورود Google باز نشد. دوباره تلاش کنید.',
              en: 'The Google sign-in page did not open. Try again.',
            ));
      }
    } on TimeoutException {
      if (mounted) setState(() => _error = _timeoutError());
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = _safeAuthError(error));
    } catch (_) {
      if (mounted) setState(() => _error = _networkError());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardAware = _channel == _AuthChannel.email ||
        _phoneStage == _PhoneStage.phone ||
        _phoneStage == _PhoneStage.otp;
    final keyboardVisible =
        keyboardAware && MediaQuery.viewInsetsOf(context).bottom > 0;
    return Directionality(
      textDirection: _isPersian ? TextDirection.rtl : TextDirection.ltr,
      child: LifeMateOnboardingScaffold(
        theme: _theme,
        title: LifeMateRuntimeLocale.select(fa: 'حساب LifeMate', en: 'LifeMate account'),
        body: _buildBody(keyboardVisible: keyboardVisible),
        primaryLabel: _primaryLabel(),
        onPrimary: _busy ? null : _primaryAction(),
        primaryBusy: _busy,
        keyboardAware: keyboardAware,
        onBack: _channel == _AuthChannel.phone && _phoneStage != _PhoneStage.intent
            ? _backPhoneStage
            : null,
        secondary: _buildSecondary(),
      ),
    );
  }

  Widget _buildBody({required bool keyboardVisible}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!keyboardVisible) ...[
          const SizedBox(height: 4),
          Center(
            child: Image.asset(
              widget.logoAssetPath,
              width: 68,
              height: 68,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(color: _theme.soft, shape: BoxShape.circle),
                child: Icon(Icons.favorite_rounded, color: _theme.primary, size: 28),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ] else
          const SizedBox(height: 2),
        _channelSelector(),
        SizedBox(height: keyboardVisible ? 8 : 12),
        Expanded(
          child: Align(
            alignment: Alignment.topCenter,
            child: _channel == _AuthChannel.email
                ? _emailBody()
                : _phoneBody(),
          ),
        ),
        if (_error != null) _feedback(_error!, error: true),
        if (_message != null && !keyboardVisible)
          _feedback(_message!, error: false),
      ],
    );
  }

  Widget _channelSelector() {
    if (!_phoneEnabled) {
      return Center(
        child: Text(
          LifeMateRuntimeLocale.select(fa: 'ورود با ایمیل', en: 'Continue with email'),
          style: TextStyle(
            color: _theme.muted,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    return SegmentedButton<_AuthChannel>(
      segments: [
        ButtonSegment(
          value: _AuthChannel.phone,
          icon: const Icon(Icons.phone_android_rounded, size: 19),
          label: Text(LifeMateRuntimeLocale.select(fa: 'شماره موبایل', en: 'Mobile')),
        ),
        ButtonSegment(
          value: _AuthChannel.email,
          icon: const Icon(Icons.alternate_email_rounded, size: 19),
          label: Text(LifeMateRuntimeLocale.select(fa: 'ایمیل', en: 'Email')),
        ),
      ],
      selected: {_channel},
      onSelectionChanged: (value) => _selectChannel(value.first),
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
        visualDensity: VisualDensity.compact,
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
        ),
        backgroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? _theme.surface : _theme.surfaceAlt),
        foregroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? _theme.primary : _theme.muted),
        side: WidgetStatePropertyAll(BorderSide(color: _theme.border)),
      ),
    );
  }

  Widget _authQuestion({required String title, String? description}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: TextStyle(
            color: _theme.ink,
            fontSize: 20,
            height: 1.35,
            fontWeight: FontWeight.w900,
          ),
        ),
        if (description != null) ...[
          const SizedBox(height: 6),
          Text(
            description,
            style: TextStyle(
              color: _theme.muted,
              fontSize: 13,
              height: 1.45,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }

  Widget _emailBody() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _authQuestion(
          title: _emailMode == _EmailMode.signIn
              ? LifeMateRuntimeLocale.select(fa: 'خوش برگشتی', en: 'Welcome back')
              : LifeMateRuntimeLocale.select(fa: 'ساخت حساب LifeMate', en: 'Create your LifeMate account'),
          description: _emailMode == _EmailMode.signIn
              ? LifeMateRuntimeLocale.select(
                  fa: 'با ایمیل و رمز عبور خود ادامه بده.',
                  en: 'Continue with your email and password.',
                )
              : LifeMateRuntimeLocale.select(
                  fa: 'بعد از تأیید حساب، نام و هدف استفاده را در چند قدم کوتاه تکمیل می‌کنی.',
                  en: 'After verification, you will complete your name and intent in a few short steps.',
                ),
        ),
        const SizedBox(height: 14),
        LifeMateOnboardingTextField(
          theme: _theme,
          controller: _email,
          label: LifeMateRuntimeLocale.select(fa: 'آدرس ایمیل', en: 'Email address'),
          hintText: 'name@example.com',
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          textDirection: TextDirection.ltr,
          autofillHints: const [AutofillHints.email],
          enabled: !_busy,
        ),
        const SizedBox(height: 10),
        LifeMateOnboardingTextField(
          theme: _theme,
          controller: _password,
          label: LifeMateRuntimeLocale.select(fa: 'رمز عبور', en: 'Password'),
          textInputAction: _emailMode == _EmailMode.signIn
              ? TextInputAction.done
              : TextInputAction.next,
          textDirection: TextDirection.ltr,
          obscureText: _obscurePassword,
          enabled: !_busy,
          suffix: IconButton(
            tooltip: LifeMateRuntimeLocale.select(
              fa: _obscurePassword ? 'نمایش رمز' : 'پنهان کردن رمز',
              en: _obscurePassword ? 'Show password' : 'Hide password',
            ),
            onPressed: _busy
                ? null
                : () => setState(() => _obscurePassword = !_obscurePassword),
            icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
          ),
          onSubmitted: _emailMode == _EmailMode.signIn ? (_) => _submitEmail() : null,
        ),
        if (_emailMode == _EmailMode.signUp) ...[
          const SizedBox(height: 10),
          LifeMateOnboardingTextField(
            theme: _theme,
            controller: _confirmPassword,
            label: LifeMateRuntimeLocale.select(fa: 'تکرار رمز عبور', en: 'Confirm password'),
            textInputAction: TextInputAction.done,
            textDirection: TextDirection.ltr,
            obscureText: _obscureConfirm,
            enabled: !_busy,
            suffix: IconButton(
              tooltip: LifeMateRuntimeLocale.select(
                fa: _obscureConfirm ? 'نمایش رمز' : 'پنهان کردن رمز',
                en: _obscureConfirm ? 'Show password' : 'Hide password',
              ),
              onPressed: _busy
                  ? null
                  : () => setState(() => _obscureConfirm = !_obscureConfirm),
              icon: Icon(_obscureConfirm ? Icons.visibility_outlined : Icons.visibility_off_outlined),
            ),
            onSubmitted: (_) => _submitEmail(),
          ),
        ],
      ],
    );
  }

  Widget _phoneBody() {
    if (!_phoneEnabled) return const SizedBox.shrink();
    return switch (_phoneStage) {
      _PhoneStage.intent => _phoneIntentBody(),
      _PhoneStage.phone => _phoneNumberBody(),
      _PhoneStage.otp => _otpBody(),
    };
  }

  Widget _phoneIntentBody() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _authQuestion(
          title: LifeMateRuntimeLocale.select(
            fa: 'با این شماره چه کاری می‌خواهی انجام بدهی؟',
            en: 'How do you want to continue with this number?',
          ),
          description: LifeMateRuntimeLocale.select(
            fa: 'برای جلوگیری از ساخت حساب تکراری، ورود و ثبت‌نام موبایلی عمداً جدا هستند.',
            en: 'Mobile sign-in and signup are intentionally separate to prevent duplicate accounts.',
          ),
        ),
        const SizedBox(height: 14),
        LifeMateOnboardingOptionCard(
          theme: _theme,
          title: LifeMateRuntimeLocale.select(fa: 'از قبل حساب دارم', en: 'I already have an account'),
          subtitle: LifeMateRuntimeLocale.select(
            fa: 'ورود با شماره‌ای که قبلاً به LifeMate وصل شده',
            en: 'Sign in with a number already linked to LifeMate',
          ),
          icon: Icons.login_rounded,
          selected: false,
          onTap: () => _selectPhoneIntent(LifeMatePhoneOtpIntent.signIn),
        ),
        const SizedBox(height: 10),
        LifeMateOnboardingOptionCard(
          theme: _theme,
          title: LifeMateRuntimeLocale.select(fa: 'حساب جدید می‌سازم', en: 'Create a new account'),
          subtitle: LifeMateRuntimeLocale.select(
            fa: 'فقط اگر قبلاً حساب LifeMate نداری',
            en: 'Only if you do not already have a LifeMate account',
          ),
          icon: Icons.person_add_alt_1_rounded,
          selected: false,
          onTap: () => _selectPhoneIntent(LifeMatePhoneOtpIntent.signUp),
        ),
      ],
    );
  }

  Widget _phoneNumberBody() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _authQuestion(
          title: LifeMateRuntimeLocale.select(fa: 'شماره موبایل را وارد کن', en: 'Enter your mobile number'),
          description: LifeMateRuntimeLocale.select(
            fa: 'برای دریافت کد تأیید، شماره موبایل ایرانی خودت را وارد کن.',
            en: 'Enter your Iranian mobile number to receive a verification code.',
          ),
        ),
        const SizedBox(height: 14),
        LifeMateOnboardingTextField(
          theme: _theme,
          controller: _phone,
          label: LifeMateRuntimeLocale.select(fa: 'شماره موبایل', en: 'Mobile number'),
          hintText: '09123456789',
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.done,
          textDirection: TextDirection.ltr,
          autofillHints: const [AutofillHints.telephoneNumber],
          enabled: !_busy,
          onSubmitted: (_) => _sendPhoneCode(),
        ),
      ],
    );
  }

  Widget _otpBody() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _authQuestion(
          title: LifeMateRuntimeLocale.select(fa: 'کد تأیید', en: 'Verification code'),
          description: LifeMateRuntimeLocale.select(
            fa: 'کدی را که برای شماره واردشده ارسال شده وارد کن.',
            en: 'Enter the code sent to the mobile number you provided.',
          ),
        ),
        const SizedBox(height: 14),
        LifeMateOtpInput(
          theme: _theme,
          controller: _otp,
          length: 6,
          enabled: !_busy,
          error: _error != null,
          onCompleted: (_) => _verifyPhoneCode(),
        ),
      ],
    );
  }

  Widget _feedback(String text, {required bool error}) {
    final color = error ? _theme.error : _theme.success;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(error ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
              color: color, size: 17),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 12,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _primaryLabel() {
    if (_channel == _AuthChannel.email) {
      return _emailMode == _EmailMode.signIn
          ? LifeMateRuntimeLocale.select(fa: 'ورود', en: 'Sign in')
          : LifeMateRuntimeLocale.select(fa: 'ساخت حساب', en: 'Create account');
    }
    return switch (_phoneStage) {
      _PhoneStage.intent => LifeMateRuntimeLocale.select(fa: 'یک گزینه را انتخاب کن', en: 'Choose an option'),
      _PhoneStage.phone => LifeMateRuntimeLocale.select(fa: 'دریافت کد', en: 'Send code'),
      _PhoneStage.otp => LifeMateRuntimeLocale.select(fa: 'تأیید و ادامه', en: 'Verify and continue'),
    };
  }

  VoidCallback? _primaryAction() {
    if (_channel == _AuthChannel.email) return _submitEmail;
    return switch (_phoneStage) {
      _PhoneStage.intent => null,
      _PhoneStage.phone => _sendPhoneCode,
      _PhoneStage.otp => _otp.text.length >= 6 ? _verifyPhoneCode : null,
    };
  }

  Widget _buildSecondary() {
    if (_channel == _AuthChannel.email) {
      return Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [
          TextButton(
            onPressed: _busy
                ? null
                : () => _setEmailMode(
                      _emailMode == _EmailMode.signIn
                          ? _EmailMode.signUp
                          : _EmailMode.signIn,
                    ),
            child: Text(
              _emailMode == _EmailMode.signIn
                  ? LifeMateRuntimeLocale.select(fa: 'حساب جدید', en: 'Create account')
                  : LifeMateRuntimeLocale.select(fa: 'قبلاً حساب دارم', en: 'I already have an account'),
            ),
          ),
          if (_emailMode == _EmailMode.signIn)
            TextButton(
              onPressed: _busy ? null : _resetPassword,
              child: Text(LifeMateRuntimeLocale.select(fa: 'رمز را فراموش کردم', en: 'Forgot password')),
            ),
          if (_googleEnabled)
            TextButton.icon(
              onPressed: _busy ? null : _signInWithGoogle,
              icon: const Icon(Icons.account_circle_outlined, size: 18),
              label: const Text('Google'),
            ),
        ],
      );
    }
    if (_phoneStage == _PhoneStage.otp) {
      final canResend = _resendSeconds == 0 && !_busy;
      return Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        children: [
          TextButton(
            onPressed: _busy ? null : _backPhoneStage,
            child: Text(LifeMateRuntimeLocale.select(fa: 'ویرایش شماره', en: 'Edit number')),
          ),
          TextButton(
            onPressed: canResend ? _sendPhoneCode : null,
            child: Text(
              _resendSeconds == 0
                  ? LifeMateRuntimeLocale.select(fa: 'ارسال مجدد', en: 'Resend')
                  : LifeMateRuntimeLocale.select(
                      fa: 'ارسال مجدد تا $_resendSeconds ثانیه',
                      en: 'Resend in $_resendSeconds s',
                    ),
            ),
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  }
}
