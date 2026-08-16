import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'feature_flags.dart';
import 'iran_phone.dart';
import 'lifemate_auth.dart';
import 'locale_digit_input_formatter.dart';
import 'runtime_locale.dart';

typedef LifeMateEmailChangeRequest = Future<void> Function(String email);
typedef LifeMateRecoveryRequest = Future<void> Function(String email);
typedef LifeMateIdentityLinkRequest = Future<void> Function();
typedef LifeMatePhoneChangeRequest = Future<void> Function(String phoneE164);
typedef LifeMatePhoneChangeVerification = Future<void> Function(
  String phoneE164,
  String token,
);

class LifeMateAccountSecurityController {
  const LifeMateAccountSecurityController({
    required this.currentEmail,
    required this.requestEmailChange,
    required this.requestPasswordRecovery,
    required this.linkGoogleIdentity,
    this.currentPhone,
    this.requestPhoneChange,
    this.verifyPhoneChange,
  });

  factory LifeMateAccountSecurityController.supabase({
    required SupabaseClient client,
    required String appName,
  }) {
    final callback = kIsWeb ? null : LifeMateAuth.callbackUrlForApp(appName);
    return LifeMateAccountSecurityController(
      currentEmail: client.auth.currentUser?.email?.trim(),
      currentPhone: client.auth.currentUser?.phone?.trim(),
      requestEmailChange: (email) async {
        await client.auth.updateUser(
          UserAttributes(email: email),
          emailRedirectTo: callback,
        );
      },
      requestPasswordRecovery: (email) => client.auth.resetPasswordForEmail(
        email,
        redirectTo: callback,
      ),
      linkGoogleIdentity: () async {
        await client.auth.linkIdentity(
          OAuthProvider.google,
          redirectTo: callback,
        );
      },
      requestPhoneChange: (phoneE164) async {
        await client.auth.updateUser(UserAttributes(phone: phoneE164));
      },
      verifyPhoneChange: (phoneE164, token) async {
        await client.auth.verifyOTP(
          phone: phoneE164,
          token: token,
          type: OtpType.phoneChange,
        );
      },
    );
  }

  final String? currentEmail;
  final String? currentPhone;
  final LifeMateEmailChangeRequest requestEmailChange;
  final LifeMateRecoveryRequest requestPasswordRecovery;
  final LifeMateIdentityLinkRequest linkGoogleIdentity;
  final LifeMatePhoneChangeRequest? requestPhoneChange;
  final LifeMatePhoneChangeVerification? verifyPhoneChange;
}

class LifeMateAccountSecurityScreen extends StatefulWidget {
  const LifeMateAccountSecurityScreen({
    required this.controller,
    required this.accent,
    required this.background,
    required this.ink,
    this.googleLinkingEnabled = LifeMateFeatureFlags.googleAuthEnabled,
    this.phoneLinkingEnabled = LifeMateFeatureFlags.phoneOtpEnabled,
    super.key,
  });

  final LifeMateAccountSecurityController controller;
  final Color accent;
  final Color background;
  final Color ink;
  final bool googleLinkingEnabled;
  final bool phoneLinkingEnabled;

  @override
  State<LifeMateAccountSecurityScreen> createState() =>
      _LifeMateAccountSecurityScreenState();
}

class _LifeMateAccountSecurityScreenState
    extends State<LifeMateAccountSecurityScreen> {
  final _emailController = TextEditingController();
  final _emailFormKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController(text: '09');
  final _phoneFormKey = GlobalKey<FormState>();
  final _phoneOtpController = TextEditingController();
  bool _emailBusy = false;
  bool _recoveryBusy = false;
  bool _linkBusy = false;
  bool _phoneBusy = false;
  String? _pendingEmail;
  String? _pendingPhone;
  String? _verifiedPhone;
  _SecurityNotice? _notice;

  bool get _phoneActionsAvailable =>
      widget.phoneLinkingEnabled &&
      widget.controller.requestPhoneChange != null &&
      widget.controller.verifyPhoneChange != null;

  @override
  void initState() {
    super.initState();
    _verifiedPhone = _normalizedPhoneOrNull(widget.controller.currentPhone);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _phoneController.dispose();
    _phoneOtpController.dispose();
    super.dispose();
  }

  String? _validateEmail(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) {
      return LifeMateRuntimeLocale.select(
        fa: 'ایمیل جدید را وارد کنید.',
        en: 'Enter the new email address.',
      );
    }
    if (value.length > 254 ||
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value)) {
      return LifeMateRuntimeLocale.select(
        fa: 'فرمت ایمیل معتبر نیست.',
        en: 'Enter a valid email address.',
      );
    }
    if (value.toLowerCase() ==
        widget.controller.currentEmail?.trim().toLowerCase()) {
      return LifeMateRuntimeLocale.select(
        fa: 'این همان ایمیل فعلی است.',
        en: 'This is already your current email.',
      );
    }
    return null;
  }

  String? _validatePhone(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) {
      return LifeMateRuntimeLocale.select(
        fa: 'شماره موبایل جدید را وارد کنید.',
        en: 'Enter the new mobile number.',
      );
    }
    final normalized = _normalizedPhoneOrNull(value);
    if (normalized == null) {
      return LifeMateRuntimeLocale.select(
        fa: 'شماره موبایل ایران معتبر وارد کنید.',
        en: 'Enter a valid Iranian mobile number.',
      );
    }
    if (normalized == _verifiedPhone) {
      return LifeMateRuntimeLocale.select(
        fa: 'این همان شماره موبایل تأییدشده فعلی است.',
        en: 'This is already your current verified mobile number.',
      );
    }
    return null;
  }

  Future<void> _changeEmail() async {
    if (_emailBusy || !(_emailFormKey.currentState?.validate() ?? false)) return;
    final email = _emailController.text.trim();
    setState(() {
      _emailBusy = true;
      _notice = null;
    });
    try {
      await widget.controller.requestEmailChange(email);
      if (!mounted) return;
      setState(() {
        _pendingEmail = email;
        _emailController.clear();
        _notice = _SecurityNotice.success(
          LifeMateRuntimeLocale.select(
            fa: 'درخواست تغییر ایمیل ثبت شد. تا وقتی تأییدهای لازم انجام نشود، ایمیل فعلی حساب را تغییر‌یافته در نظر نمی‌گیریم.',
            en: 'Email change requested. Your current account email remains authoritative until the required confirmation is completed.',
          ),
        );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _notice = _SecurityNotice.error(
          LifeMateRuntimeLocale.select(
            fa: 'شروع تغییر ایمیل ممکن نشد. کمی بعد دوباره تلاش کنید.',
            en: 'Email change could not be started. Try again later.',
          ),
        );
      });
    } finally {
      if (mounted) setState(() => _emailBusy = false);
    }
  }

  Future<void> _requestPhoneChange() async {
    if (_phoneBusy || !_phoneActionsAvailable) return;
    if (!(_phoneFormKey.currentState?.validate() ?? false)) return;
    final phone = _normalizedPhoneOrNull(_phoneController.text);
    if (phone == null) return;

    setState(() {
      _phoneBusy = true;
      _notice = null;
    });
    try {
      await widget.controller.requestPhoneChange!(phone);
      if (!mounted) return;
      setState(() {
        _pendingPhone = phone;
        _phoneOtpController.clear();
        _notice = _SecurityNotice.success(
          LifeMateRuntimeLocale.select(
            fa: 'درخواست تغییر شماره ثبت شد. تا پیش از تأیید کد، شماره فعلی حساب تغییر‌یافته در نظر گرفته نمی‌شود.',
            en: 'Phone change requested. The current verified number remains authoritative until the code is confirmed.',
          ),
        );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _notice = _SecurityNotice.error(
          LifeMateRuntimeLocale.select(
            fa: 'شروع تغییر شماره موبایل ممکن نشد. کمی بعد دوباره تلاش کنید.',
            en: 'Phone change could not be started. Try again later.',
          ),
        );
      });
    } finally {
      if (mounted) setState(() => _phoneBusy = false);
    }
  }

  Future<void> _verifyPhoneChange() async {
    if (_phoneBusy || !_phoneActionsAvailable || _pendingPhone == null) return;
    final token = _phoneOtpController.text.trim();
    if (!RegExp(r'^\d{6,10}$').hasMatch(token)) {
      setState(() {
        _notice = _SecurityNotice.error(
          LifeMateRuntimeLocale.select(
            fa: 'کد تأیید معتبر وارد کنید.',
            en: 'Enter a valid verification code.',
          ),
        );
      });
      return;
    }

    final pendingPhone = _pendingPhone!;
    setState(() {
      _phoneBusy = true;
      _notice = null;
    });
    try {
      await widget.controller.verifyPhoneChange!(pendingPhone, token);
      if (!mounted) return;
      setState(() {
        _verifiedPhone = pendingPhone;
        _pendingPhone = null;
        _phoneController.text = '09';
        _phoneOtpController.clear();
        _notice = _SecurityNotice.success(
          LifeMateRuntimeLocale.select(
            fa: 'شماره موبایل این حساب تأیید و به‌روزرسانی شد. هویت سلامت یا Person جدیدی ساخته نشد.',
            en: 'This account mobile number was verified and updated. No new LifeMate health identity or Person was created.',
          ),
        );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _notice = _SecurityNotice.error(
          LifeMateRuntimeLocale.select(
            fa: 'کد تأیید پذیرفته نشد یا منقضی شده است. دوباره تلاش کنید.',
            en: 'The verification code was not accepted or has expired. Try again.',
          ),
        );
      });
    } finally {
      if (mounted) setState(() => _phoneBusy = false);
    }
  }

  Future<void> _requestRecovery() async {
    if (_recoveryBusy) return;
    final email = widget.controller.currentEmail?.trim();
    if (email == null || email.isEmpty) {
      setState(() {
        _notice = _SecurityNotice.error(
          LifeMateRuntimeLocale.select(
            fa: 'برای این حساب ایمیل قابل استفاده‌ای پیدا نشد.',
            en: 'No usable email is available for this account.',
          ),
        );
      });
      return;
    }
    setState(() {
      _recoveryBusy = true;
      _notice = null;
    });
    try {
      await widget.controller.requestPasswordRecovery(email);
      if (!mounted) return;
      setState(() {
        _notice = _SecurityNotice.success(
          LifeMateRuntimeLocale.select(
            fa: 'اگر ارسال ایمیل بازیابی برای این حساب مجاز باشد، راهنمای ادامه برایتان ارسال می‌شود.',
            en: 'If recovery delivery is available for this account, the next-step instructions will be sent.',
          ),
        );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _notice = _SecurityNotice.error(
          LifeMateRuntimeLocale.select(
            fa: 'درخواست بازیابی فعلاً انجام نشد. کمی بعد دوباره تلاش کنید.',
            en: 'Recovery could not be requested right now. Try again later.',
          ),
        );
      });
    } finally {
      if (mounted) setState(() => _recoveryBusy = false);
    }
  }

  Future<void> _linkGoogle() async {
    if (_linkBusy || !widget.googleLinkingEnabled) return;
    setState(() {
      _linkBusy = true;
      _notice = null;
    });
    try {
      await widget.controller.linkGoogleIdentity();
      if (!mounted) return;
      setState(() {
        _notice = _SecurityNotice.success(
          LifeMateRuntimeLocale.select(
            fa: 'ادامه اتصال حساب Google باز شد. اتصال فقط به همین حساب واردشده انجام می‌شود.',
            en: 'Google linking has started. The identity is linked only to the currently signed-in account.',
          ),
        );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _notice = _SecurityNotice.error(
          LifeMateRuntimeLocale.select(
            fa: 'اتصال حساب انجام نشد. تنظیمات ارائه‌دهنده یا وضعیت ورود را بررسی کنید.',
            en: 'Account linking could not be started. Check provider availability and your signed-in session.',
          ),
        );
      });
    } finally {
      if (mounted) setState(() => _linkBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentEmail = widget.controller.currentEmail?.trim();
    return Scaffold(
      backgroundColor: widget.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: Text(
          LifeMateRuntimeLocale.select(
            fa: 'امنیت حساب',
            en: 'Account security',
          ),
          style: TextStyle(color: widget.ink, fontWeight: FontWeight.w900),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
        children: [
          _SecurityCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionTitle(
                  icon: Icons.alternate_email_rounded,
                  color: widget.accent,
                  title: LifeMateRuntimeLocale.select(
                    fa: 'ایمیل ورود',
                    en: 'Sign-in email',
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  currentEmail?.isNotEmpty == true
                      ? currentEmail!
                      : LifeMateRuntimeLocale.select(
                          fa: 'ایمیل تأییدشده‌ای نمایش داده نمی‌شود.',
                          en: 'No verified email is available to display.',
                        ),
                  key: const ValueKey('account-security-current-email'),
                  style: TextStyle(
                    color: widget.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (_pendingEmail != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    key: const ValueKey('account-security-pending-email'),
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: widget.accent.withValues(alpha: .09),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      LifeMateRuntimeLocale.select(
                        fa: 'در انتظار تأیید: $_pendingEmail',
                        en: 'Pending confirmation: $_pendingEmail',
                      ),
                      style: TextStyle(color: widget.ink),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Form(
                  key: _emailFormKey,
                  child: TextFormField(
                    key: const ValueKey('account-security-new-email'),
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    validator: _validateEmail,
                    decoration: InputDecoration(
                      labelText: LifeMateRuntimeLocale.select(
                        fa: 'ایمیل جدید',
                        en: 'New email',
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const ValueKey('account-security-change-email'),
                    onPressed: _emailBusy ? null : _changeEmail,
                    style: FilledButton.styleFrom(backgroundColor: widget.accent),
                    icon: _emailBusy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.mark_email_read_rounded),
                    label: Text(
                      LifeMateRuntimeLocale.select(
                        fa: 'ارسال تأیید تغییر ایمیل',
                        en: 'Send email-change confirmation',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _SecurityCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionTitle(
                  icon: Icons.phone_android_rounded,
                  color: widget.accent,
                  title: LifeMateRuntimeLocale.select(
                    fa: 'شماره موبایل ورود',
                    en: 'Sign-in mobile number',
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _verifiedPhone == null
                      ? LifeMateRuntimeLocale.select(
                          fa: 'شماره موبایل تأییدشده‌ای برای این حساب ثبت نشده است.',
                          en: 'No verified mobile number is attached to this account.',
                        )
                      : _maskedPhone(_verifiedPhone!),
                  key: const ValueKey('account-security-current-phone'),
                  style: TextStyle(
                    color: widget.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _phoneActionsAvailable
                      ? LifeMateRuntimeLocale.select(
                          fa: 'شماره جدید فقط به همین حساب واردشده متصل می‌شود و پس از تأیید کد معتبر می‌گردد.',
                          en: 'A new number is attached only to this signed-in account and becomes authoritative only after code verification.',
                        )
                      : LifeMateRuntimeLocale.select(
                          fa: 'تغییر شماره موبایل برای این نسخه هنوز فعال نشده است.',
                          en: 'Mobile-number changes are not enabled for this release yet.',
                        ),
                  style: const TextStyle(color: Color(0xFF687386), height: 1.45),
                ),
                const SizedBox(height: 14),
                Form(
                  key: _phoneFormKey,
                  child: TextFormField(
                    key: const ValueKey('account-security-new-phone'),
                    controller: _phoneController,
                    enabled: _phoneActionsAvailable && !_phoneBusy && _pendingPhone == null,
                    keyboardType: TextInputType.phone,
                    textDirection: TextDirection.ltr,
                    inputFormatters: const [LifeMateLocaleDigitInputFormatter()],
                    validator: _validatePhone,
                    decoration: InputDecoration(
                      labelText: LifeMateRuntimeLocale.select(
                        fa: 'شماره موبایل جدید',
                        en: 'New mobile number',
                      ),
                      hintText: '09121234567',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const ValueKey('account-security-change-phone'),
                    onPressed: _phoneActionsAvailable && !_phoneBusy && _pendingPhone == null
                        ? _requestPhoneChange
                        : null,
                    style: FilledButton.styleFrom(backgroundColor: widget.accent),
                    icon: _phoneBusy && _pendingPhone == null
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.sms_outlined),
                    label: Text(
                      LifeMateRuntimeLocale.select(
                        fa: 'ارسال کد تأیید شماره',
                        en: 'Send phone-change code',
                      ),
                    ),
                  ),
                ),
                if (_pendingPhone != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    key: const ValueKey('account-security-pending-phone'),
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: widget.accent.withValues(alpha: .09),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      LifeMateRuntimeLocale.select(
                        fa: 'در انتظار تأیید: ${_maskedPhone(_pendingPhone!)}',
                        en: 'Pending verification: ${_maskedPhone(_pendingPhone!)}',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('account-security-phone-otp'),
                    controller: _phoneOtpController,
                    enabled: !_phoneBusy,
                    keyboardType: TextInputType.number,
                    textDirection: TextDirection.ltr,
                    inputFormatters: const [LifeMateLocaleDigitInputFormatter()],
                    maxLength: 10,
                    decoration: InputDecoration(
                      labelText: LifeMateRuntimeLocale.select(
                        fa: 'کد تأیید',
                        en: 'Verification code',
                      ),
                      counterText: '',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onSubmitted: (_) => _verifyPhoneChange(),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      key: const ValueKey('account-security-verify-phone'),
                      onPressed: _phoneBusy ? null : _verifyPhoneChange,
                      icon: _phoneBusy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.verified_user_outlined),
                      label: Text(
                        LifeMateRuntimeLocale.select(
                          fa: 'تأیید شماره جدید',
                          en: 'Verify new number',
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          _SecurityCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionTitle(
                  icon: Icons.password_rounded,
                  color: widget.accent,
                  title: LifeMateRuntimeLocale.select(
                    fa: 'بازیابی رمز عبور',
                    en: 'Password recovery',
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  LifeMateRuntimeLocale.select(
                    fa: 'برای تغییر امن رمز، مسیر بازیابی تأییدشده را دوباره از ایمیل شروع کنید.',
                    en: 'Restart the verified recovery flow from your email before changing the password.',
                  ),
                  style: const TextStyle(color: Color(0xFF687386), height: 1.45),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const ValueKey('account-security-recovery'),
                  onPressed: _recoveryBusy ? null : _requestRecovery,
                  icon: _recoveryBusy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.lock_reset_rounded),
                  label: Text(
                    LifeMateRuntimeLocale.select(
                      fa: 'ارسال راهنمای بازیابی',
                      en: 'Send recovery instructions',
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _SecurityCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionTitle(
                  icon: Icons.link_rounded,
                  color: widget.accent,
                  title: LifeMateRuntimeLocale.select(
                    fa: 'حساب‌های متصل',
                    en: 'Linked accounts',
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  widget.googleLinkingEnabled
                      ? LifeMateRuntimeLocale.select(
                          fa: 'می‌توانید Google را به همین حساب فعلی متصل کنید؛ این کار حساب سلامت جدیدی نمی‌سازد.',
                          en: 'You can link Google to this current account; linking does not create a second LifeMate health identity.',
                        )
                      : LifeMateRuntimeLocale.select(
                          fa: 'اتصال Google برای این نسخه هنوز از سمت تنظیمات انتشار فعال نشده است.',
                          en: 'Google linking is not enabled for this release configuration yet.',
                        ),
                  style: const TextStyle(color: Color(0xFF687386), height: 1.45),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const ValueKey('account-security-link-google'),
                  onPressed: widget.googleLinkingEnabled && !_linkBusy
                      ? _linkGoogle
                      : null,
                  icon: _linkBusy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_link_rounded),
                  label: Text(
                    LifeMateRuntimeLocale.select(
                      fa: widget.googleLinkingEnabled
                          ? 'اتصال Google'
                          : 'اتصال Google — غیرفعال',
                      en: widget.googleLinkingEnabled
                          ? 'Link Google'
                          : 'Link Google — disabled',
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_notice != null) ...[
            const SizedBox(height: 14),
            _NoticeCard(notice: _notice!),
          ],
        ],
      ),
    );
  }

  static String? _normalizedPhoneOrNull(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    try {
      return LifeMateIranPhone.normalizeE164(value);
    } on FormatException {
      return null;
    }
  }

  static String _maskedPhone(String phoneE164) {
    final normalized = _normalizedPhoneOrNull(phoneE164);
    if (normalized == null) return '••••';
    return '+98 ••• •• ${normalized.substring(normalized.length - 4)}';
  }
}

class _SecurityCard extends StatelessWidget {
  const _SecurityCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(
              color: Color(0x10000000),
              blurRadius: 22,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: child,
      );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.icon,
    required this.color,
    required this.title,
  });

  final IconData icon;
  final Color color;
  final String title;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: .11),
            foregroundColor: color,
            child: Icon(icon),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      );
}

class _SecurityNotice {
  const _SecurityNotice(this.message, this.isError);
  const _SecurityNotice.success(String message) : this(message, false);
  const _SecurityNotice.error(String message) : this(message, true);

  final String message;
  final bool isError;
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.notice});
  final _SecurityNotice notice;

  @override
  Widget build(BuildContext context) => Container(
        key: const ValueKey('account-security-notice'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: notice.isError
              ? const Color(0xFFFFECEC)
              : const Color(0xFFEAF8F0),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              notice.isError
                  ? Icons.error_outline_rounded
                  : Icons.verified_user_outlined,
              color: notice.isError
                  ? const Color(0xFFB74D4D)
                  : const Color(0xFF3F7A5A),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(notice.message)),
          ],
        ),
      );
}
