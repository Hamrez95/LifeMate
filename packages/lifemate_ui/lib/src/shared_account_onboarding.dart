import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';

import 'onboarding_components.dart';
import 'onboarding_theme.dart';

/// Server-backed minimal account onboarding shared by LifeMate products.
///
/// The gate deliberately owns only Display Name and presentation intent.
/// Birth date, healthcare data, relationships, consent and permissions remain
/// feature-specific progressive profiling and are never inferred here.
class LifeMateAccountOnboardingGate extends StatefulWidget {
  const LifeMateAccountOnboardingGate({
    super.key,
    required this.child,
    this.api,
  });

  final Widget child;
  final LifeMateAccountOnboardingApi? api;

  @override
  State<LifeMateAccountOnboardingGate> createState() =>
      _LifeMateAccountOnboardingGateState();
}

class _LifeMateAccountOnboardingGateState
    extends State<LifeMateAccountOnboardingGate> {
  late LifeMateAccountOnboardingApi _api;
  late bool _ownsApi;
  final _displayName = TextEditingController();
  LifeMateAccountOnboardingSnapshot? _snapshot;
  LifeMatePresentationIntent? _intent;
  Object? _loadError;
  String? _actionError;
  bool _loading = true;
  bool _saving = false;
  int _step = 0;

  bool get _isPersian => LifeMateRuntimeLocale.isPersian;
  LifeMateOnboardingTheme get _theme => LifeMateOnboardingTheme.shared;

  @override
  void initState() {
    super.initState();
    _ownsApi = widget.api == null;
    _api = widget.api ?? LifeMateAccountOnboardingApi.fromEnvironment();
    _load();
  }

  @override
  void didUpdateWidget(covariant LifeMateAccountOnboardingGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.api, widget.api)) return;
    if (_ownsApi) _api.close();
    _ownsApi = widget.api == null;
    _api = widget.api ?? LifeMateAccountOnboardingApi.fromEnvironment();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
        _actionError = null;
      });
    }
    try {
      final snapshot = await _api.getSnapshot();
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _intent = snapshot.presentationIntent;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _loading = false;
      });
    }
  }

  void _continueName() {
    final value = _displayName.text.trim();
    if (value.isEmpty) {
      setState(() => _actionError = LifeMateRuntimeLocale.select(
            fa: 'نامی که دوست داری در LifeMate ببینی وارد کن.',
            en: 'Enter the name you want to see in LifeMate.',
          ));
      return;
    }
    if (value.length > 120) {
      setState(() => _actionError = LifeMateRuntimeLocale.select(
            fa: 'نام واردشده بیش از حد طولانی است.',
            en: 'The entered name is too long.',
          ));
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _actionError = null;
      _step = 1;
    });
  }

  Future<void> _complete() async {
    final snapshot = _snapshot;
    final intent = _intent;
    if (snapshot == null || intent == null || _saving) return;
    setState(() {
      _saving = true;
      _actionError = null;
    });
    try {
      final updated = await _api.complete(
        current: snapshot,
        displayName: _displayName.text,
        intent: intent,
      );
      if (!mounted) return;
      setState(() {
        _snapshot = updated;
        _saving = false;
      });
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      if (error.statusCode == 409) {
        setState(() => _saving = false);
        await _reloadAfterConflict();
        return;
      }
      setState(() {
        _saving = false;
        _actionError = _safeActionError();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _actionError = _safeActionError();
      });
    }
  }

  Future<void> _reloadAfterConflict() async {
    final preservedName = _displayName.text;
    final preservedIntent = _intent;
    try {
      final latest = await _api.getSnapshot();
      if (!mounted) return;
      if (latest.completed) {
        setState(() => _snapshot = latest);
        return;
      }
      setState(() {
        _snapshot = latest;
        _intent = preservedIntent;
        _displayName.text = preservedName;
        _actionError = LifeMateRuntimeLocale.select(
          fa: 'اطلاعات حساب تازه شد؛ دوباره ادامه بده.',
          en: 'Your account information was refreshed. Continue again.',
        );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _actionError = _safeActionError());
    }
  }

  String _safeActionError() => LifeMateRuntimeLocale.select(
        fa: 'ذخیره انجام نشد. اتصال را بررسی و دوباره تلاش کن.',
        en: 'Could not save. Check your connection and try again.',
      );

  @override
  void dispose() {
    _displayName.dispose();
    if (_ownsApi) _api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    if (!_loading && _loadError == null && snapshot?.completed == true) {
      return widget.child;
    }
    if (_loading) return _loadingScreen();
    if (_loadError != null || snapshot == null) return _errorScreen();
    return _step == 0 ? _nameScreen() : _intentScreen();
  }

  Widget _loadingScreen() {
    return Directionality(
      textDirection: _isPersian ? TextDirection.rtl : TextDirection.ltr,
      child: LifeMateOnboardingScaffold(
        theme: _theme,
        title: 'LifeMate',
        primaryLabel: LifeMateRuntimeLocale.select(fa: 'در حال آماده‌سازی', en: 'Preparing'),
        primaryBusy: true,
        body: Center(
          child: LifeMateOnboardingQuestion(
            theme: _theme,
            title: LifeMateRuntimeLocale.select(
              fa: 'حساب تو را آماده می‌کنیم',
              en: 'Preparing your account',
            ),
            description: LifeMateRuntimeLocale.select(
              fa: 'چند لحظه صبر کن.',
              en: 'This only takes a moment.',
            ),
            icon: Icons.favorite_outline_rounded,
            alignCenter: true,
          ),
        ),
      ),
    );
  }

  Widget _errorScreen() {
    return Directionality(
      textDirection: _isPersian ? TextDirection.rtl : TextDirection.ltr,
      child: LifeMateOnboardingScaffold(
        theme: _theme,
        title: 'LifeMate',
        primaryLabel: LifeMateRuntimeLocale.select(fa: 'تلاش دوباره', en: 'Try again'),
        onPrimary: _load,
        body: Center(
          child: LifeMateOnboardingQuestion(
            theme: _theme,
            title: LifeMateRuntimeLocale.select(
              fa: 'اطلاعات حساب در دسترس نیست',
              en: 'Account information is unavailable',
            ),
            description: LifeMateRuntimeLocale.select(
              fa: 'اتصال را بررسی کن و دوباره تلاش کن. چیزی تغییر نکرده است.',
              en: 'Check your connection and try again. Nothing was changed.',
            ),
            icon: Icons.cloud_off_outlined,
            alignCenter: true,
          ),
        ),
      ),
    );
  }

  Widget _nameScreen() {
    return Directionality(
      textDirection: _isPersian ? TextDirection.rtl : TextDirection.ltr,
      child: LifeMateOnboardingScaffold(
        theme: _theme,
        title: LifeMateRuntimeLocale.select(fa: 'شروع LifeMate', en: 'Start LifeMate'),
        progress: 0.5,
        progressLabel: LifeMateRuntimeLocale.select(fa: '۱ از ۲', en: '1 of 2'),
        primaryLabel: LifeMateRuntimeLocale.select(fa: 'ادامه', en: 'Continue'),
        onPrimary: _continueName,
        keyboardAware: true,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Spacer(),
            LifeMateOnboardingQuestion(
              theme: _theme,
              title: LifeMateRuntimeLocale.select(
                fa: 'دوست داری چه صدات کنیم؟',
                en: 'What should we call you?',
              ),
              description: LifeMateRuntimeLocale.select(
                fa: 'این نام در بخش‌های مختلف حساب و تجربه شخصی تو نمایش داده می‌شود.',
                en: 'This name appears across your account and personal experience.',
              ),
              icon: Icons.person_outline_rounded,
              alignCenter: true,
            ),
            const SizedBox(height: 26),
            LifeMateOnboardingTextField(
              theme: _theme,
              controller: _displayName,
              label: LifeMateRuntimeLocale.select(fa: 'نام نمایشی', en: 'Display name'),
              hintText: LifeMateRuntimeLocale.select(fa: 'مثلاً حمیدرضا', en: 'For example, Alex'),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _continueName(),
              enabled: !_saving,
            ),
            if (_actionError != null) ...[
              const SizedBox(height: 10),
              _feedback(_actionError!),
            ],
            const Spacer(flex: 2),
          ],
        ),
      ),
    );
  }

  Widget _intentScreen() {
    return Directionality(
      textDirection: _isPersian ? TextDirection.rtl : TextDirection.ltr,
      child: LifeMateOnboardingScaffold(
        theme: _theme,
        title: LifeMateRuntimeLocale.select(fa: 'شروع LifeMate', en: 'Start LifeMate'),
        progress: 1,
        progressLabel: LifeMateRuntimeLocale.select(fa: '۲ از ۲', en: '2 of 2'),
        primaryLabel: LifeMateRuntimeLocale.select(fa: 'ورود به LifeMate', en: 'Enter LifeMate'),
        onPrimary: _intent == null || _saving ? null : _complete,
        primaryBusy: _saving,
        onBack: _saving ? null : () => setState(() {
          _step = 0;
          _actionError = null;
        }),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Spacer(),
            LifeMateOnboardingQuestion(
              theme: _theme,
              title: LifeMateRuntimeLocale.select(
                fa: 'LifeMate را بیشتر برای چه کاری می‌خواهی؟',
                en: 'What will you mainly use LifeMate for?',
              ),
              description: LifeMateRuntimeLocale.select(
                fa: 'این انتخاب فقط مسیر و محتوای اولیه را شخصی‌سازی می‌کند و هیچ دسترسی درمانی ایجاد نمی‌کند.',
                en: 'This only personalizes your starting experience and never grants healthcare access.',
              ),
            ),
            const SizedBox(height: 22),
            _intentCard(
              LifeMatePresentationIntent.self,
              Icons.person_outline_rounded,
              LifeMateRuntimeLocale.select(fa: 'برای خودم', en: 'For myself'),
              LifeMateRuntimeLocale.select(
                fa: 'داروها، برنامه‌ها و سلامت شخصی',
                en: 'My medication, plans and personal health',
              ),
            ),
            const SizedBox(height: 12),
            _intentCard(
              LifeMatePresentationIntent.caregiving,
              Icons.favorite_border_rounded,
              LifeMateRuntimeLocale.select(fa: 'برای مراقبت از دیگری', en: 'To care for someone'),
              LifeMateRuntimeLocale.select(
                fa: 'همراهی و مراقبت با رضایت صاحب اطلاعات',
                en: 'Caregiving with the data owner’s consent',
              ),
            ),
            const SizedBox(height: 12),
            _intentCard(
              LifeMatePresentationIntent.both,
              Icons.diversity_1_outlined,
              LifeMateRuntimeLocale.select(fa: 'هر دو', en: 'Both'),
              LifeMateRuntimeLocale.select(
                fa: 'ابتدا تجربه شخصی؛ اتصال CareMate بعداً و اختیاری',
                en: 'Personal experience first; CareMate connection stays optional',
              ),
            ),
            if (_actionError != null) ...[
              const SizedBox(height: 10),
              _feedback(_actionError!),
            ],
            const Spacer(flex: 2),
          ],
        ),
      ),
    );
  }

  Widget _intentCard(
    LifeMatePresentationIntent intent,
    IconData icon,
    String title,
    String subtitle,
  ) {
    return LifeMateOnboardingOptionCard(
      theme: _theme,
      title: title,
      subtitle: subtitle,
      icon: icon,
      selected: _intent == intent,
      enabled: !_saving,
      onTap: () => setState(() {
        _intent = intent;
        _actionError = null;
      }),
    );
  }

  Widget _feedback(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline_rounded, color: _theme.error, size: 18),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: _theme.error,
              fontSize: 12.5,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
